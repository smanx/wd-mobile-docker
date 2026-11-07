# wd-mobile-docker

把「某道·八周年」**移动端**（安卓客户端 + `magic_s1` 服务端）打包成 Docker 镜像的项目。
客户端为安卓 APK（MuMu 模拟器实测），服务端二进制文件**零修改**：原始 zip 原样放进镜像，
构建时解压到与原教程一致的路径；所有环境差异与历史遗留问题（EOL 源、若依配置、TLS、
区服下发地址等）都在构建/启动脚本层解决。

> ✅ **状态：已完整跑通并验证。** 全新机器（干净数据卷）一次部署即可：登录 → 选服 →
> 进入游戏 → 创建角色，全链路实测通过（见下方「实测验证」）。

## 项目结构

```
wd-mobile-docker/
├── server/
│   ├── wd-parts/                  # 原始服务端包的分卷（wd.zip + wd.z01/z02/...，每卷 <100MB 入库）
│   ├── assemble-wdzip.sh          # 构建前把分卷合并还原成 wd.zip（322MB）。CI/本地都靠它
│   └── wd.zip                     # 合并产物（gitignore；由 assemble-wdzip.sh 生成）
├── client/                        # 已改好 IP、重签名的安卓客户端产物（不入库）
├── docker/
│   ├── Dockerfile                 # 单容器全家桶：CentOS 7.6 + MySQL 5.6 + PHP 5.4 + Redis 6.2 + JDK 8 + 32位库
│   ├── entrypoint.sh              # 启动：导库 → 数据适配 → mysqld/redis/php-fpm/nginx → 可选拉起游戏
│   ├── adapt.sh                   # 数据层幂等适配：若依密码、90sdk、gddb、区服下发地址、TLS 证书
│   ├── loadsql.sh                 # 数据库导入（对应 /home/s1/sql/loadsql，修正了原脚本变量笔误）
│   ├── sources.repo               # CentOS vault 源（默认阿里云镜像）
│   ├── epel.repo                  # EPEL 归档源（阿里云镜像）
│   ├── mysql56.repo               # MySQL 5.6 官方 yum 源（repo.mysql.com）
│   ├── my.cnf                     # MySQL 5.6 配置
│   ├── nginx.conf                 # stream 分流：81/80/443 自动区分 HTTP/HTTPS；88 → 代理后台
│   ├── www.conf                   # PHP-FPM pool
│   ├── redis.conf                 # Redis 6.2 配置
│   └── start-services.sh          # 服务进程看护（mysqld/redis/php-fpm/nginx）
├── tests/
│   ├── healthcheck.sh             # 全面体检（服务/端口/HTTP/游戏/数据配置/持久化）
│   ├── smoke-test.sh              # 冒烟测试（构建后 15 项）
│   ├── status.sh                  # 运行状态速查
│   └── win-hosts.ps1              # （客户端联调用）Windows hosts 半自动辅助
├── .github/workflows/docker.yml   # GitHub Actions：自动构建并发布镜像
├── Makefile                       # image / run / status / stop / clean
├── run.sh                         # 一键运行
└── README.md
```

## 为什么是单容器

原项目按「宝塔 + CentOS 7.6 一体机」设计，存在大量硬编码：游戏进程按绝对路径读写
`/home/s1/**`；PHP 直连 `127.0.0.1:3306`；代理后台（若依 JAR）与 Nginx 同机。
单容器可保持所有项目文件原样，一次构建即得完整可运行环境。

## 快速开始（WSL2 / Linux，x86_64）

```bash
# 1) 构建镜像（约 2GB，视网络 10-20 分钟）
make image

# 2) 运行（用持久化数据卷，首次自动导入 11 个数据库 + 全套适配）
make run
#   等价于：
#   docker run -d --name wd-server --restart unless-stopped --shm-size=1g \
#     -v wd-mysql-data:/var/lib/mysql \
#     -p 81:81 -p 80:80 -p 443:443 -p 88:88 -p 9877:9877 -p 3306:3306 -p 6379:6379 \
#     -p 10001-10310:10001-10310 \
#     -e AUTO_START_GAME=1 wd-server:latest

# 3) 体检
make status      # 或 bash tests/healthcheck.sh
```

`AUTO_START_GAME=1` 会随容器自动拉起 14 个游戏进程；也可手动：

```bash
docker exec -it wd-server bash
/home/s1/qd                   # 启动游戏进程
/home/daili/ry.sh restart     # 启动代理后台
/home/s1/stop                 # 停止游戏
```

## 实测验证

### 全新部署（干净数据卷，等同首次装机）—— 全部自动生效

| 检查项 | 结果 |
|---|---|
| magic_s1 游戏进程 | ✅ 22 个全部存活 |
| MySQL 5.6 / Redis 6.2 | ✅ 存活 / PONG |
| 11 个业务库 | ✅ 全部导入 |
| release_adb.server 区服下发地址 | ✅ 自动改为可达地址（关键，见下） |
| gddb 库（aaa 启动校验） | ✅ 自动补建 |
| TLS 证书（81/443 分流） | ✅ 自动生成 |
| HTTP 81 / 88、HTTPS 443 | ✅ 均 200 |

### 客户端端到端（MuMu 模拟器 + 改 IP 客户端）

登录 → 同意协议 → 选服「官方问道 梦幻一区」→ **进入游戏** → **到达创建角色界面**，
实测客户端与游戏认证服（10001）、游戏线（10201）均建立 ESTABLISHED 连接。

## 关键修复记录（供参考）

> 这些都是原包的「历史遗留坑」，已在镜像/启动脚本中解决，使用者无需再处理。

**构建/环境层**
- centos:7 基础层 x86_64 库太老，装 i686 会触发 `Protected multilib versions`，
  必须先 `yum -y update` 再装 i686 包；
- `mysqld_safe` 只允许 mysql 用户在 `/tmp|/var/tmp|/var/log/mysql|$DATADIR` 白名单内
  新建日志文件，`/wd/logs` 必须预创建并 chown；
- Dockerfile 的 RUN 结尾不要用 `|| true`，会把 yum 失败吞进构建缓存；
- CentOS 7 / MySQL 5.6 已 EOL：yum 源用阿里云 vault 镜像，Redis 6.2 源码编译。

**Web/后台层**
- `reg.html` 会 JS 跳转到原打包者 IP → 构建期全局替换为本地地址；
- `/gm/` 目录 `index.html` 是宝塔默认页，nginx `index` 必须先 `index.php`；
- 若依 jar 写死数据库密码 `QQ24460571` 且主库 `90sdk` 缺失 → 外部配置覆盖密码 + 建最小 90sdk；
- 验证码图片渲染 NPE：最小容器缺字体 → 装 fontconfig + dejavu 字体。

**客户端接入层（登录卡 loading / 进入游戏卡 loading 的根因）**
- 客户端 SDK 登录请求走 `https://`，且部分域名是 https。nginx 用 **stream `ssl_preread`
  协议分流**：81/80/443 自动识别 TLS 转给 HTTPS 后端、明文转 HTTP 后端，一套端口两者共存；
  `assets/sdkConfig` 里硬编码的原服务器 IP 无法直接改，故用 **hosts 劫持/路由劫持**把
  `*.leiting1.com` 与旧 IP 指向本机；
- PHP 登录接口 `api.php` 用 `mcrypt` 做 DES 解密 → 镜像必须装 `php-mcrypt`；
- **进入游戏卡 loading 的根因**：aaa 认证通过后会把 `release_adb.server` 表的 `ip/outer_ip`
  下发给客户端作为游戏线地址，原包是 `127.0.0.1`（客户端连自己回环）→ `adapt.sh` 启动时
  自动改成 `CLIENT_IP`（默认 `172.29.220.175`，可用环境变量覆盖）；
- aaa 启动会校验 `gddb` 库（原 sql 包里叫 `release_gddb`）→ `adapt.sh` 自动补建 `gddb`。

## 端口

| 端口 | 用途 |
|---|---|
| 81 / 80 / 443 | 注册 / GM / CDK / 玩家后台（同一后端；81/80 明文、443 及 81/80 上的 TLS 走 HTTPS 后端） |
| 88 | 代理后台（若依 UI，反代 9877） |
| 9877 | 若依 API |
| 3306 / 6379 | MySQL / Redis（建议不对外映射） |
| 10001 | 游戏认证服 aaa（客户端登录后连这里） |
| 10201–10310 | 各游戏线 gs（客户端选服后连这里） |

> 网络：容器用 **bridge + 端口映射**（`-p`）。客户端（模拟器/手机）连的是这些映射端口。
> 若客户端 IP 与容器网段不同，请把 `CLIENT_IP` 环境变量设为客户端可达的宿主机地址
> （`docker run -e CLIENT_IP=<你的IP> ...`），`adapt.sh` 会用该地址下发区服。

## 服务端原始包的存放（分卷）

`server/wd.zip` 原包 322MB，超过 GitHub 100MB 单文件限制，无法直接入库。
因此本项目把服务端包**解压后重新做成 zip 分卷**（`server/wd-parts/`，每卷 90MB），
完整入库；构建镜像前由 `server/assemble-wdzip.sh` 合并还原成 `server/wd.zip`：

```bash
bash server/assemble-wdzip.sh   # 合并 wd-parts → server/wd.zip（已存在则跳过）
```

`make image` 和 GitHub Actions 都会自动执行这一步，无需手动操作。
分卷已逐文件 MD5 校验，还原后与原包**完全一致**（629 个文件全匹配）。

## GitHub Actions

`.github/workflows/docker.yml`：push 到 `main` 或手动触发时，用 buildx 构建 `linux/amd64`
镜像并发布到 GHCR（`ghcr.io/<owner>/wd-mobile-docker`），无需任何 secrets——
服务端分卷已在仓库里，workflow 会自动合并后构建。

## 注意事项

- 宿主机必须是 **x86_64**（二进制是 32 位 i386 ELF + JIT，ARM 不可用）。
- 内存建议 ≥ 16GB（教程要求游戏进程共占 13GB；仅验证服务可 8GB）。
- **MySQL 数据务必挂持久卷**（`-v wd-mysql-data:/var/lib/mysql`），否则容器重建会丢账号。
- Windows 侧「插件.zip」是易语言程序，不能进 Linux 容器，按原架构放在 Windows 机器上。
- 客户端需改 IP：把 `PlatformConfig.luac` / `classes.dex` 里的旧 IP 替换为你的地址并重签名；
  详见 `client/` 产物与本文「客户端接入层」说明。
- 本项目是**移动端**（安卓 APK）；PC 端不在本项目范围内。
- 仅供学习研究，请勿用于商业用途。
