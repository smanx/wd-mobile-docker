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

# 2) 运行（持久化数据卷；游戏随容器自动启动，首次启动约 4~5 分钟完成全部初始化）
docker run -d --name wd-server --restart unless-stopped --init --shm-size=1g \
  -v wd-mysql-data:/var/lib/mysql \
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
  -e CLIENT_IP=<客户端可达的本机地址> \
  ghcr.io/smanx/wd-mobile-docker:latest
```

Linux 宿主机对外开服时也可以直接 host 网络（性能略好，无需 -p）：

```bash
docker run -d --name wd-server --restart unless-stopped --init --shm-size=1g \
  --network host \
  -v wd-mysql-data:/var/lib/mysql \
  -e CLIENT_IP=<服务器公网IP> \
  ghcr.io/smanx/wd-mobile-docker:latest
```

> 注意：host 网络模式下 `CLIENT_IP` 不能是 127.0.0.1，必须是外部可达地址。

**host 网络下的"全端口映射版"**：host 模式里容器直接监听宿主机所有地址，
等价于把**全部端口都映射出去了**。如果需要只暴露游戏必需端口、隐藏
数据库/缓存等内部端口，改用 bridge + 精确映射即可——对照表如下：

| host 模式实际暴露 | bridge 建议映射 | 用途 | 是否对外 |
|---|---|---|---|
| 81 / 80 / 443 | ✅ `-p 81:81 -p 80:80 -p 443:443` | 注册/GM/后台/SDK HTTPS | 必须对外 |
| 88 | ✅ `-p 88:88` | 代理后台（若依 UI） | 必须对外 |
| 9877 | ✅ `-p 9877:9877` | 若依 API（88 反代它） | 必须对外 |
| 10001 | ✅ `-p 10001:10001` | aaa 认证服（客户端登录后连） | 必须对外 |
| 10201–10210 | ✅ `-p 10201-10210:10201-10210` | gs 游戏线（客户端选服后连） | 必须对外 |
| 3306 | ❌ 不映射 | MySQL | **绝不对外** |
| 6379 | ❌ 不映射 | Redis | **绝不对外** |
| 10301–10310 | ❌ 不映射 | gs 的 telnet 管理口（运维用） | 建议不对外 |
| 2701–2711 等 | ❌ 不映射 | 服务间内部 RPC（aaa/dba/ccs…互联） | **绝不对外** |
| 50004+ 等 | ❌ 不映射 | 内部临时 RPC | **绝不对外** |

**安卓客户端实际用到的端口只有 5 组**（实测抓包确认）：
`81`（版本/热更/配置/登录接口）、`443`（SDK 账密登录 HTTPS）、`88`（游戏内注册页 WebView）、
`10001`（认证服 aaa）、`10201-10210`（游戏线 gs，只连选中的那条）。
只开服给玩家的话，最小映射集就是这 5 组；`9877` 和 `10301-10310`（telnet 管理口）
玩家用不到，按需决定是否对外。

即：**host 网络 = 一切端口直通宿主机**（3306/6379 也直接裸奔在公网上，
务必靠防火墙/安全组挡住）；**bridge + 精确 -p = 只对外暴露上表需要的端口**，
这是推荐给公网部署的安全姿势。

> 额外提醒：两种模式下 3306/6379 都存在弱口令账号（教程自带的密码体系），
> 公网机器务必用安全组/防火墙封死这两个端口，只允许本机或管理机访问。

### 首次启动会发生什么（自动完成，无需干预）

1. 初始化 MySQL 数据目录（仅首次）→ 设 root 密码 → 导入 11 个业务库；
2. 数据适配（幂等，每次启动都会跑一遍，已适配则跳过）：
   - `release_adb.server`：`ip=127.0.0.1`、`outer_ip=CLIENT_IP`；
   - `patch/dist.lua`：区服地址改写为 `CLIENT_IP:10001`；
   - 预置测试账号 `admin1/admin1`（可直接登录）；
   - 生成含 SDK 域名 SAN 的自签 TLS 证书；
3. 拉起 mysqld/redis/php-fpm/nginx → 启动基础设施服务（aaa/dba/ldba/csa/ccs 等）；
4. **等 aaa 真正监听 10001 后**再启动 10 条 gs 游戏线（aaa 内置最多 5 次启动重试）；
5. gs 游戏线拉起后还要加载大量游戏内容（地图/任务/活动脚本），**再等约 1~2 分钟才真正
   可登录**——整个流程从 `docker run` 到可进游戏约 **5 分钟**。期间客户端显示
   「服务器正在维护中」是正常的预热状态，等日志出现 `allows user to login` 即可进入。

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

游戏随容器自动启动（无需任何开关）。需要手动干预时：

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

| 端口 | 用途 | 客户端使用 |
|---|---|---|
| 81 / 80 / 443 | 注册 / GM / CDK / 玩家后台（同一后端；81/80 明文、443 及 81/80 上的 TLS 走 HTTPS 后端） | ✅ 81 与 443（80 为备用别名） |
| 88 | 代理后台（若依 UI，反代 9877） | ✅（游戏内注册页 WebView） |
| 9877 | 若依 API | ❌（仅 88 反代内部访问） |
| 3306 / 6379 | MySQL / Redis | ❌（服务端内部，建议不对外映射） |
| 10001 | 游戏认证服 aaa（客户端登录后连这里） | ✅ |
| 10201–10210 | 各游戏线 gs（客户端选服后连选中的那条） | ✅ |
| 10301–10310 | gs 的 telnet 管理口 | ❌（运维用，建议不对外） |
| 2701–2711 等 | 服务间内部 RPC（aaa/dba/ccs/ldba…互联） | ❌（绝不对外） |

> **客户端最小端口集：81、443、88、10001、10201-10210**（其余端口玩家用不到）。

## 部署完成后的使用方法（来自原版搭建教程）

以下信息来自 `手工端/搭建教程.txt`（原版 CentOS 7.6 + Windows Server 2012 手工架设教程），
Docker 镜像已把服务端的部署步骤全部自动化，但**网页入口、账号、GM 码、客户端 IP 常量**
这些信息仍以原教程为准。

### 网页入口

| 入口 | 地址 | 口令/邀请码 |
|---|---|---|
| 玩家注册 | `http://<服务器IP>:81/reg.html` | 邀请码 `A1` |
| GM 后台 | `http://<服务器IP>:81/gm/gm.php` | GM 码 `51boshao.com` |
| 玩家后台 | `http://<服务器IP>:81/gm/` | — |
| CDK 兑换 | `http://<服务器IP>:81/gm/cdk` | GM 码 `51boshao.com` |
| 代理后台（若依） | `http://<服务器IP>:88` | — |

> `<服务器IP>` 用浏览器所在机器能访问到的地址（本机可 `127.0.0.1`，局域网/公网用
> `CLIENT_IP`）。容器版的 81 端口由 nginx 直接提供站点，无需宝塔创建网站。

### 数据库与账号数据

| 项目 | 值 | 说明 |
|---|---|---|
| MySQL root 密码 | `j4Tj3vq1ih6` | 原教程要求统一改成这个 |
| MySQL 最大连接数 | `30000` (`max_connections`) | 已在 `my.cnf` 固化 |
| 业务库 | `release_adb/ddb/gddb/gsdb/ldb/mdb/sdb/sldb/tdb`、`account`、`wdgm`（共 11 个） | 首次启动由 `loadsql.sh` 自动导入 |
| 插件数据库账号 | 用户 `W1G=1LA*3` / 密码 `Hrr1dkVU8S@W1G=LA*3HwMsqtrUZWQ72n` | 原教程授权给 Windows 插件机；镜像里已授予 `'%'` |
| 预置测试账号 | `admin1` / `admin1` | 镜像自动写入 `account.account`，可直接在游戏里登录 |
| 账号密码算法 | `strtoupper(md5(账号 + strtoupper(md5(密码)) + "xiaowu2023"))` | 注册接口写入、SDK 登录校验都用这个 |
| Windows 插件库 | 库名 `plugin`，导入 `plugin.sql` | 易语言插件专用，在 Windows 侧建，不进 Linux 容器 |

连接示例（容器内或映射了 3306 的宿主机上）：

```bash
mysql -h127.0.0.1 -P3306 -u root -pj4Tj3vq1ih6
```

### 原教程的手工运维命令（Docker 版已自动处理，供对照）

| 原教程步骤 | Docker 镜像里的对应行为 |
|---|---|
| `cd /home/s1 && ./qd`（启动游戏，需 13G 内存） | 随容器自动启动，且按依赖顺序 + 端口就绪重试 |
| `cd /home/daili && sh ry.sh restart`（启动代理） | 随容器自动启动 |
| `cd /home/s1 && ./stop`（关闭游戏） | 直接 `docker stop wd-server` 即可 |
| `find /home -type d -name "log" -exec rm -r {} +`（清理日志） | 日志统一输出到 `/wd/logs/`，按需清理 |
| `find /home /www/wwwroot -type f ... sed -i s/114.132.177.234/你的IP/` | 构建期已全局替换，运行期由 `adapt.sh` 改 `server` 表与 `dist.lua` |
| 宝塔里建站点 `ip:81` 指向 `/www/wwwroot/game` | `nginx.conf` 已配好，无需宝塔 |
| 宝塔放行 1-65535、关防火墙 `systemctl stop firewalld` | 容器无 firewalld；宿主机/安全组按需放行（见端口表） |
| `chmod -R 777 /home/ /www/wwwroot/`、`mv /home/qz /bin` | 构建期已处理 |

### 客户端与其它数据（原教程）

- **需要替换的硬编码 IP 常量**：服务端文件里是 `114.132.177.234`（原教程让你改成服务器 IP）；
  客户端 APK 里是 `49.235.188.189`（改成 Linux 服务器 IP）。两者是不同的值，别改混。
- **服务端需手工改 IP 的文件**（原版教程列出，Docker 版已自动处理）：
  - `/www/wwwroot/game/wd/110001_config_20190415.json`（原教程说要"配合解密工具修改"）
  - `patch.zip` 内 `patch/dist.lua`（原教程要求改成 **WIN 系统服务器 IP**）
  - `patch.zip` 内 `patch/patch_url.lua`、`patch/patch_url_ats.lua`
- **安卓客户端**：`assets/res/PlatformConfig.luac`、`classes.dex`（反编译后批量替换），
  替换后需重算 dex 校验并重签名；详见本文件「客户端接入」章节。
- **iOS 客户端**：需要企业签名才能进游戏，替换
  `Payload/AsktaoMobile iOS.app/key.json` 与
  `Payload/AsktaoMobile iOS.app/res/PlatformConfig.luac`。
- **Windows 插件端**（易语言，不能进 Linux 容器）：解压 `插件.zip`，安装常用运行库合集 /
  N++ / E2EE.ODBC / N11 数据库管理工具；改 `插件/Config.data` 第 38 行（插件 IP = WIN 服务器
  IP）、第 48 行（主服务器 IP = Linux 服务器 IP）；用 N11 连接数据库后建 `plugin` 库、导入
  `plugin.sql`，最后运行「周年插件稳定运行.exe」→ 链接数据库 → 启动插件。
- **原环境版本**：nginx-1.18 / MySQL-5.6 / PHP-5.4 / Redis-6.2；测试系统 CentOS 7.6 +
  Windows Server 2012；游戏进程原教程要求 ≥13G 内存（不够就加虚拟内存）。
- **原包出处**：源码屋 `www.51boshao.com`，默认解压密码 `www.51boshao.com`，交流群
  `131646129`。原教程声明**仅供单机研究学习、勿用于商业用途、下载后 24 小时内删除**，
  本项目沿用同样的定位。

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
- **启动很慢，请耐心等待约 5 分钟再登录！** 容器启动后服务只是刚拉起，游戏服务器（gs）
  还要加载地图/任务/活动脚本等大量内容，**必须等全部就绪才能进**；
  提前登录选区会显示「服务器正在维护中」——这不是故障，是还没预热完，等一会儿再点即可；
- 分阶段时间参考（容器启动后计）：约 1.5 分钟基础设施全部监听 → 约 2 分钟 gs 进程拉起
  → **约 4~5 分钟 gs 加载完毕、真正可登录**；
- 判断就绪的可靠方法（出现即表示全部游戏线已开放登录）：

  ```bash
  docker exec wd-server grep -ac "allows user to login" /wd/logs/game_rungs.log
  # 输出 10 = 10 条游戏线全部就绪，可以登录了
  ```

  （gs 端口 10201-10210 全监听只是"进程起来了"，不代表"加载完了"，以日志为准）
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
- **host 网络模式 = 全端口直通宿主机**（含 3306/6379 和内部 RPC 端口），公网机器必须用
  防火墙/安全组封死非游戏端口；想只暴露游戏端口请用 bridge + 精确 `-p`（见端口对照表）；
- SDK 登录域名（`*.leiting1.com`）必须劫持到服务器 IP，否则账密登录报「网络请求异常/账号不存在」。

**客户端**
- APK 里 IP 替换必须**等长**（dex/luac 是连续字符串，破坏长度会损坏文件），改完重签名；
- 模拟器重装 APK / 清数据后，hosts 劫持会丢，需重新配置；
- 出现「热更删除 APK 后不自动重启」：多为 81 端口 version.php 不可达（hosts/网络问题），
  修好网络重装 APK 即可。

**其他**
- Windows 侧「插件.zip」是易语言程序，不能进 Linux 容器；其配置（`Config.data` 的
  插件 IP / 主服务器 IP）、`plugin` 库与 `plugin.sql` 导入等详见
  「部署完成后的使用方法 → 客户端与其它数据」章节；
- 注册邀请码 `A1`、GM 码 `51boshao.com`、数据库 root 密码 `j4Tj3vq1ih6` 等
  原版数据详见「部署完成后的使用方法」章节；
- 本项目是**移动端**（安卓 APK）；PC 端不在本项目范围内；
- 仅供学习研究，请勿用于商业用途。
