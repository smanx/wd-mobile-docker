# wd-mobile-docker

把「某道·八周年」**移动端**（安卓客户端 + `magic_s1` 服务端）打包成 Docker 镜像的项目。
客户端为安卓 APK（MuMu 模拟器实测），服务端二进制文件**零修改**：原始 zip 原样放进镜像，
构建时解压到与原教程一致的路径；所有环境差异与历史遗留问题（EOL 源、若依配置、TLS、
区服下发地址、进程启动顺序等）都在构建/启动脚本层解决。

> ✅ **状态：已完整跑通并验证。** 使用在线镜像 + 全新数据卷，一次部署、零手工干预：
> 登录 → 选服 → 进入游戏 → 创建角色 → 进入游戏世界，全链路实测通过（见下方「实测验证」）。

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
│   │                              #   并在构建期移除各服务 run 脚本里的 --enable-socket-daemon 1（见「关键修复」）
│   ├── entrypoint.sh              # 启动：初始化/导库 → 数据适配 → 交给 start-services
│   ├── adapt.sh                   # 数据层幂等适配：若依密码、90sdk、区服地址分工、dist.lua、TLS 证书、预置账号
│   ├── loadsql.sh                 # 数据库导入（对应 /home/s1/sql/loadsql，修正了原脚本变量笔误）
│   ├── sources.repo               # CentOS vault 源（默认阿里云镜像）
│   ├── epel.repo                  # EPEL 归档源（阿里云镜像）
│   ├── mysql56.repo               # MySQL 5.6 官方 yum 源（repo.mysql.com）
│   ├── my.cnf                     # MySQL 5.6 配置（latin1 全局，见「关键修复」）
│   ├── nginx.conf                 # stream 分流：81/80/443 自动区分 HTTP/HTTPS；88 → 代理后台
│   ├── www.conf                   # PHP-FPM pool
│   ├── redis.conf                 # Redis 6.2 配置
│   └── start-services.sh          # 运行时启动：mysqld_safe 看护 + 先基础设施、aaa 就绪后再起 gs
├── .github/workflows/docker.yml   # GitHub Actions：自动构建并发布镜像
├── Makefile                       # image / run / status / stop / clean
├── run.sh                         # 一键运行
└── README.md
```

## 为什么是单容器

原项目按「宝塔 + CentOS 7.6 一体机」设计，存在大量硬编码：游戏进程按绝对路径读写
`/home/s1/**`；PHP 直连 `127.0.0.1:3306`；代理后台（若依 JAR）与 Nginx 同机。
单容器可保持所有项目文件原样，一次构建即得完整可运行环境。

## 方式一：直接使用在线镜像部署（推荐）

镜像已发布到 GHCR，无需本地构建，拉下来即可跑（x86_64，约 2GB）：

```bash
# 1) 拉取镜像
docker pull ghcr.io/smanx/wd-mobile-docker:latest

# 2) 运行（持久化数据卷 + 自动启动游戏；首次启动约 4~5 分钟完成全部初始化）
docker run -d --name wd-server --restart unless-stopped --init --shm-size=1g \
  -v wd-mysql-data:/var/lib/mysql \
  -e AUTO_START_GAME=1 \
  -e CLIENT_IP=<客户端可达的本机地址> \
  ghcr.io/smanx/wd-mobile-docker:latest
```

### `CLIENT_IP` 必须设置正确（最常见的坑）

它决定两处配置：
- `release_adb.server.outer_ip`：aaa 认证通过后**下发给客户端**的「游戏线连接地址」；
- `patch/dist.lua` 的 `aaa` 地址：客户端**选服时**连接的认证服地址。

规则一句话：**`CLIENT_IP` = 你的模拟器/手机能连通的那个地址**（不是容器内网 IP，更不能是 127.0.0.1）。

| 场景 | CLIENT_IP 取值 |
|---|---|
| 模拟器/手机和 Docker 在同一台机器（WSL2 部署） | WSL 的对外 IP 或 Windows 侧做了端口转发的地址 |
| 云服务器对外开服 | 服务器的公网 IP |
| 局域网内其他设备要玩 | 宿主机的局域网 IP |

> 表内 `ip` 字段保持 `127.0.0.1`（服务端 gs 在容器内部绑定它），`outer_ip` 才是给客户端的地址，
> 两者分工固定，无需手工修改数据库。

### 端口映射版（bridge）与 host 网络版

bridge + `-p` 映射（默认推荐）：

```bash
docker run -d --name wd-server --restart unless-stopped --init --shm-size=1g \
  -v wd-mysql-data:/var/lib/mysql \
  -p 81:81 -p 80:80 -p 443:443 -p 88:88 -p 9877:9877 -p 3306:3306 -p 6379:6379 \
  -p 10001-10310:10001-10310 \
  -e AUTO_START_GAME=1 -e CLIENT_IP=<客户端可达的本机地址> \
  ghcr.io/smanx/wd-mobile-docker:latest
```

Linux 宿主机对外开服时也可以直接 host 网络（性能略好，无需 -p）：

```bash
docker run -d --name wd-server --restart unless-stopped --init --shm-size=1g \
  --network host \
  -v wd-mysql-data:/var/lib/mysql \
  -e AUTO_START_GAME=1 -e CLIENT_IP=<服务器公网IP> \
  ghcr.io/smanx/wd-mobile-docker:latest
```

> 注意：host 网络模式下 `CLIENT_IP` 不能是 127.0.0.1，必须是外部可达地址。

### 首次启动会发生什么（自动完成，无需干预）

1. 初始化 MySQL 数据目录（仅首次）→ 设 root 密码 → 导入 11 个业务库；
2. 数据适配（幂等，每次启动都会跑一遍，已适配则跳过）：
   - `release_adb.server`：`ip=127.0.0.1`、`outer_ip=CLIENT_IP`；
   - `patch/dist.lua`：区服地址改写为 `CLIENT_IP:10001`；
   - 预置测试账号 `admin1/admin1`（可直接登录）；
   - 生成含 SDK 域名 SAN 的自签 TLS 证书；
3. 拉起 mysqld/redis/php-fpm/nginx → 启动基础设施服务（aaa/dba/ldba/csa/ccs 等）；
4. **等 aaa 真正监听 10001 后**再启动 10 条 gs 游戏线（aaa 内置最多 5 次启动重试）。

### 如何确认已就绪

```bash
# 一条命令看核心结论：gs 游戏线端口（10201-10210）是否全部监听
docker exec wd-server sh -c \
  "cat /proc/net/tcp | awk 'NR>1{split(\$2,a,\":\");p=strtonum(\"0x\"a[2]);if(p>=10201&&p<=10210&&\$4==\"0A\")print p}' | sort -un | tr '\n' ' '"
# 输出 `10201 ... 10210` 即就绪

# 日志里看到这行说明服务端已允许登录
docker exec wd-server grep -a "allows user to login" /wd/logs/game_rungs.log | head -1
```

就绪后客户端即可登录（账号 `admin1/admin1`，或自行注册）。

## 方式二：本地构建

```bash
# 1) 构建镜像（约 2GB，视网络 10-20 分钟）
make image

# 2) 运行（同上，镜像名换成 wd-server:latest）
make run

# 3) 体检
make status      # 查看容器与各服务状态
```

手动启动/停止游戏进程（一般不需要，`AUTO_START_GAME=1` 已自动处理）：

```bash
docker exec -it wd-server bash
/home/s1/stop                   # 停止游戏
/home/daili/ry.sh restart       # 重启代理后台
# 重新启动游戏：重启容器即可（推荐），或逐个执行 /home/s1/*/run*
```

## 客户端接入（模拟器/手机）

客户端 APK 里硬编码了服务器地址，需要改 IP 并重签名（`client/` 目录是改好的产物）：

1. **APK 内 IP 替换**：`assets/res/PlatformConfig.luac`（5 处）与 `classes.dex`（7 处）
   里的旧 IP 替换为你的服务器地址。**替换必须等长**（dex/luac 里是连续字符串，
   例如 `49.235.188.189` → `172.29.220.175` 都是 14 字符），改完重算 dex 校验并重签名。
2. **SDK 域名劫持**：账密登录走雷霆 SDK 的 `https://loginali.leiting1.com` 等域名，
   需要把这些域名解析到你的服务器（nginx 已带对应证书 SAN）。模拟器 root 后改 hosts：

   ```
   172.29.220.175  static.leiting1.com login.leiting1.com loginali.leiting1.com \
                   loginsjhl.leiting1.com member.leiting1.com pay.leiting1.com payali.leiting1.com \
                   paysjhl.leiting1.com logmonitor.leiting1.com testlogin.leiting1.com \
                   testmember.leiting1.com testpay.leiting1.com testlogmonitor.leiting1.com \
                   testkernel.leiting1.com webproxy.leiting1.com helper.leiting1.com www.leiting1.com
   ```
3. **模拟器网络**：MuMu 桥接模式最省事（模拟器与宿主同网段，直接连 `CLIENT_IP`）；
   若保持 NAT 模式，需在 Windows 宿主机做端口转发（`netsh interface portproxy`）并放行防火墙，
   否则模拟器连不到 WSL2 里的容器。
4. 重装 APK 后若卡「热更/删除 APK」，多半是 hosts 未生效或 81 端口不可达导致版本检查失败。

## 实测验证（在线镜像 + 全新数据卷，零干预）

| 检查项 | 结果 |
|---|---|
| MySQL 5.6 | ✅ OK |
| 13 类 magic_s1 服务进程 | ✅ 全部存活（aaa/ccs/csa/dba/dps/gs×10/ldba/msa/mss/ps/sns/spa/tts） |
| gs 游戏线 10201-10210 | ✅ 全部监听 |
| 核心端口 10001/10002/10003/10004/10006 | ✅ 全部监听 |
| `release_adb.server` ip/outer_ip | ✅ `127.0.0.1` / `CLIENT_IP`（自动分工） |
| 预置账号 admin1 | ✅ 自动写入 |
| dist.lua 区服地址 | ✅ 自动改为 `CLIENT_IP:10001` |
| nginx 81/88/443 | ✅ 200 |
| 服务端放行登录 | ✅ `Game server allows user to login now` |
| 模拟器连 10201 | ✅ GS_OK |
| 端到端 | ✅ 登录 → 选服 → 进大区 → 创建角色 → 进入游戏世界（揽仙镇） |

## 关键修复记录（供参考）

> 这些都是踩过的「真坑」，已在镜像/启动脚本中解决，使用者无需再处理。

**构建/环境层**
- centos:7 基础层 x86_64 库太老，装 i686 会触发 `Protected multilib versions`，
  必须先 `yum -y update` 再装 i686 包；
- `mysqld_safe` 只允许 mysql 用户在白名单目录内新建日志文件，`/wd/logs` 必须预创建并 chown；
- Dockerfile 的 RUN 结尾不要用 `|| true`，会把 yum 失败吞进构建缓存；
- CentOS 7 / MySQL 5.6 已 EOL：yum 源用阿里云 vault 镜像，Redis 6.2 源码编译。

**进程启动层（gs 起不来的三大根因）**
- **`--enable-socket-daemon 1` 必须移除**：它让 magic_s1 fork 一个 socket 守护进程去 bind
  服务端口，在容器内（pid namespace/信号语义）bind 必失败 → `Bind is failed. Failed to listen
  on port: 10001` → aaa 起不来 → gs 卡 `Try to obtain game_server_list` → 客户端「服务器维护中」；
  构建期已从所有 run 脚本中删除该参数；
- **MySQL 5.6 没有 `--daemonize`**（那是 5.7+）：用 `mysqld --daemonize` 启动会直接报
  `unknown option` 退出，运行时 mysqld 永远起不来；必须用 `mysqld_safe`；
- **启动顺序**：先基础设施（aaa/dba/ldba/csa/ccs…），**等 aaa 真正监听 10001 后再起 gs**
  （gs 要向 aaa 拉取 game_server_list；全并行启动 gs 会输掉竞态）；
  另 aaa 首次 bind 偶发撞残留 TIME_WAIT，已内置最多 5 次重试；
- aaa 启动时校验数据库架构与内置 xml 一致：**不要给 `server_status` 表额外加列**
  （如 `gs_status`），多出字段会导致 aaa 拒绝启动。

**数据层（区服地址分工）**
- `release_adb.server.ip`：**保持 127.0.0.1**，是 gs 在容器内绑定用的内部地址；
- `release_adb.server.outer_ip`：**必须为客户端可达地址**（`CLIENT_IP`），aaa 把它下发给
  客户端连游戏线；两个字的分工固定，改错任何一边都会导致「进入大区连接超时」；
- `patch/dist.lua` 的 `aaa` 地址：客户端选服入口，原包是死 IP，`adapt.sh` 启动时自动改写。

**Web/后台层**
- `reg.html` 会 JS 跳转到原打包者 IP → 构建期全局替换为本地地址；
- `/gm/` 目录 `index.html` 是宝塔默认页，nginx `index` 必须先 `index.php`；
- 若依 jar 写死数据库密码 `QQ24460571` 且主库 `90sdk` 缺失 → 外部配置覆盖密码 + 建最小 90sdk；
- 验证码图片渲染 NPE：最小容器缺字体 → 装 fontconfig + dejavu 字体。

**客户端接入层**
- SDK 登录走 `https://`，nginx 用 **stream `ssl_preread` 协议分流**：81/80/443 自动识别
  TLS 转给 HTTPS 后端、明文转 HTTP 后端，一套端口两者共存；
- PHP 登录接口 `api.php` 用 `mcrypt` 做 DES 解密 → 镜像必须装 `php-mcrypt`；
- MySQL 字符集全局 **latin1**（含连接层）：服务端用 GBK 字节当 latin1 存区服名，
  连接层若是 utf8 会触发 `Illegal mix of collations`。

## 端口

| 端口 | 用途 |
|---|---|
| 81 / 80 / 443 | 注册 / GM / CDK / 玩家后台（同一后端；81/80 明文、443 及 81/80 上的 TLS 走 HTTPS 后端） |
| 88 | 代理后台（若依 UI，反代 9877） |
| 9877 | 若依 API |
| 3306 / 6379 | MySQL / Redis（建议不对外映射） |
| 10001 | 游戏认证服 aaa（客户端登录后连这里） |
| 10201–10310 | 各游戏线 gs（客户端选服后连这里） |

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

## 注意事项（部署前必读）

**硬件与系统**
- 宿主机必须是 **x86_64**（二进制是 32 位 i386 ELF + JIT，ARM 不可用）；
- 内存建议 ≥ 16GB（游戏进程 + MySQL buffer pool 共占约 13GB；仅验证服务可 8GB）；
- 磁盘预留 ≥ 10GB（镜像 2GB + 数据卷 + 日志）。

**数据持久化**
- **务必挂持久卷**：`-v wd-mysql-data:/var/lib/mysql`；
- **绝对不要 `docker rm -v` / `docker volume rm` 删数据卷**——账号、角色、充值数据全在里面；
- `docker restart` / `stop`+`start` 数据不丢，可放心重启；只有删除卷才会丢数据；
- 换 `CLIENT_IP` 重新 `docker run` 时**沿用同一个卷**，数据不会丢。

**启动与运维**
- 首次冷启动约 **4~5 分钟**（导库 11 个 + aaa 重试 + 串行启动），期间客户端连不上是正常的；
- 判断就绪：gs 端口 10201-10210 全监听 / 日志出现 `Game server allows user to login now`；
- **不要在容器里手动 `pkill magic_s1`**：游戏进程不在看护循环里，杀了不会自动拉起；
  需要重启游戏就重启容器；
- aaa 首次 bind 偶发失败属正常（内置 5 次重试），日志在 `/wd/logs/game.log`；
- 查看各服务日志：`/wd/logs/game_<服务名>.log`、`/wd/logs/mysqld.log`；
- 账号：预置 `admin1/admin1`；自行注册走客户端「账号注册」或 `POST /login/reg.php`。

**网络（最常见的失败原因都在这）**
- `CLIENT_IP` 必须是**客户端可达**的地址：设错的表现是「登录成功、选服后进入大区一直
  连接超时」（客户端拿 outer_ip 连 gs 连不上）；
- WSL2 部署时，模拟器默认 NAT 模式连不到 WSL 内网 IP：要么模拟器改桥接，要么在 Windows
  做 `netsh interface portproxy` 端口转发 + 防火墙放行（81/88/443/10001-10310）；
- 不要修改本地网卡的 IP/别名来「凑」地址——用桥接或 portproxy，避免弄断宿主机网络；
- 云服务器开服记得在安全组放行 81/88/443/9877/10001-10310；3306/6379 不要对外开放；
- SDK 登录域名（`*.leiting1.com`）必须劫持到服务器 IP，否则账密登录报「网络请求异常/账号不存在」。

**客户端**
- APK 里 IP 替换必须**等长**（dex/luac 是连续字符串，破坏长度会损坏文件），改完重签名；
- 模拟器重装 APK / 清数据后，hosts 劫持会丢，需重新配置；
- 出现「热更删除 APK 后不自动重启」：多为 81 端口 version.php 不可达（hosts/网络问题），
  修好网络重装 APK 即可。

**其他**
- Windows 侧「插件.zip」是易语言程序，不能进 Linux 容器，按原架构放在 Windows 机器上；
- 本项目是**移动端**（安卓 APK）；PC 端不在本项目范围内；
- 仅供学习研究，请勿用于商业用途。
