# =============================================================================
# wd-docker — 某道·八周年 Linux 服务端单容器镜像
#
# 设计原则：项目文件零修改。
#   - wd.zip 原样复制进镜像，解压到 / （得到 /home 与 /www/wwwroot，与原教程一致）
#   - 仅新增 /wd 装运行环境与启动脚本
#
# 基础镜像：centos:7（glibc 2.17，与教程 Centos 7.6 一致）
#   MySQL 5.6  ← repo.mysql.com yum（教程指定版本）
#   PHP 5.4    ← CentOS base（7.x 自带 5.4.16，教程指定 php-5.4）
#   Redis 6.2  ← 源码编译（教程指定 redis-6.2；EL7 的 remi 已不含 redis6）
#   JDK 8      ← java-1.8.0-openjdk（跑 ruoyi-admin-encrypted.jar）
#   32 位库    ← glibc/nss/zlib i686（magic_s1 是 32 位 ELF，需要 /lib/ld-linux.so.2）
#
# 构建上下文：仓库根目录（COPY 路径带 docker/ 前缀，与 GitHub Actions 的
#   context: . 一致；本地测试请把文件同步到 <ctx>/docker/ 后在根目录构建）
#
# 注意：任何 RUN 都不要用 "|| true" 结尾——会吞掉 yum 失败并污染构建缓存。
# =============================================================================
FROM centos:7

ARG MYSQL_ROOT_PASSWORD=j4Tj3vq1ih6
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# 1. 系统源：CentOS 7 已 EOL，官方 mirrorlist / vault 均不可靠（403/超时）。
#    默认用阿里云 centos-vault 镜像；MySQL 5.6 用 repo.mysql.com 手写 repo；
#    EPEL 用 epel-archive 镜像。
# ---------------------------------------------------------------------------
COPY docker/sources.repo /etc/yum.repos.d/CentOS-Base.repo
COPY docker/epel.repo    /etc/yum.repos.d/epel.repo
COPY docker/mysql56.repo /etc/yum.repos.d/mysql56.repo

# ---------------------------------------------------------------------------
# 2. 先全量升级到 7.9（centos:7 基础层是老版本，i686 包是 7.9，
#    不先升级会触发 yum "Protected multilib versions" 冲突）
#    然后装基础工具 + 32 位运行库（magic_s1 依赖），并自检 32 位 loader
# ---------------------------------------------------------------------------
RUN yum makecache fast && yum -y update && yum clean all && \
    yum makecache fast && yum install -y \
        wget curl tar unzip zip which \
        glibc.i686 nss-softokn-freebl.i686 \
        zlib.i686 libstdc++.i686 ncurses-libs.i686 \
        openssl-libs.i686 cyrus-sasl-lib.i686 && \
    test -f /lib/ld-linux.so.2 && \
    yum clean all

# ---------------------------------------------------------------------------
# 3. Redis 6.2 源码编译（教程指定 6.2）
#    构建依赖 gcc/make 用完即删，控制镜像体积
# ---------------------------------------------------------------------------
RUN yum install -y gcc make jemalloc-devel && \
    curl -fsSL https://download.redis.io/releases/redis-6.2.14.tar.gz -o /tmp/redis.tar.gz && \
    cd /tmp && tar xzf redis.tar.gz && cd redis-6.2.14 && \
    make -j"$(nproc)" MALLOC=libc BUILD_TLS=no >/dev/null && \
    make PREFIX=/wd/redis6 install >/dev/null && \
    rm -rf /tmp/redis* && yum remove -y gcc make jemalloc-devel && yum clean all

# ---------------------------------------------------------------------------
# 4. MySQL 5.6（教程指定版本；repo 已在步骤 1 装好）
# ---------------------------------------------------------------------------
RUN yum install -y mysql-community-server-5.6.* mysql-community-client-5.6.* mysql-community-libs-5.6.* && \
    yum clean all

# ---------------------------------------------------------------------------
# 5. PHP 5.4（CentOS 7 base 自带 5.4.16）+ nginx 1.18（教程指定，nginx.org 官方包）
# ---------------------------------------------------------------------------
COPY docker/nginx-org.repo /etc/yum.repos.d/nginx.repo
RUN yum install -y \
        php php-mysql php-gd php-xml php-mbstring php-bcmath \
        php-fpm php-process php-pdo php-mcrypt libmcrypt fontconfig dejavu-sans-fonts liberation-fonts-common \
        nginx-1.18.* && \
    yum clean all

# ---------------------------------------------------------------------------
# 6. JDK 8（ruoyi-admin-encrypted.jar 需要，-XX:+UseParallelOldGC 在新 JDK 已移除）
# ---------------------------------------------------------------------------
RUN yum install -y java-1.8.0-openjdk-headless && yum clean all

# ---------------------------------------------------------------------------
# 7. 解压原始服务端到根目录（得到 /home/s1 /home/daili /www/wwwroot/game）
#    并给权限 + 装 /bin/qz + nginx 站点配置（与教程一致）
# ---------------------------------------------------------------------------
COPY server/wd.zip /tmp/wd.zip
RUN cd / && unzip -q /tmp/wd.zip && rm -f /tmp/wd.zip && \
    chmod -R 777 /home/ && chmod -R 777 /www/wwwroot/ && \
    find /www/wwwroot/ /home/s1/ -type f -exec grep -lI '114.132.177.234' {} + 2>/dev/null | xargs -r sed -i 's/114.132.177.234/127.0.0.1/g' && \
    mv -f /home/qz /bin/qz && chmod 777 /bin/qz && \
    mv -f /home/daili/dogNG.conf /etc/nginx/conf.d/dogNG.conf && \
    ln -sfn /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo 'Asia/Shanghai' > /etc/timezone
# 关键修复：去掉各服务启动脚本里的 "--enable-socket-daemon 1"。
# 该选项会让 magic_s1 fork 一个 socket 守护进程去 bind 服务端口（如 aaa 的 10001），
# 在容器内（pid namespace + 信号语义）会导致 bind 竞争失败：
#   "Bind is failed. / Failed to listen on port: 10001 / AAA failed to listen on port: 10001"
# 结果 aaa 起不来 → gs 连不上 aaa → 卡 "Try to obtain game_server_list"，
# 游戏线 10201-10210 不监听，客户端显示“服务器维护中”。
RUN find /home/s1 -maxdepth 2 -type f -name 'run*' -exec sed -i 's/ --enable-socket-daemon 1//g' {} + && \
    grep -rl 'enable-socket-daemon' /home/s1 2>/dev/null | head -1 | grep . && echo "WARN: socket-daemon still present" || true

# ---------------------------------------------------------------------------
# 8. 配置文件：MySQL / Nginx / PHP-FPM / Redis / 启动脚本
#    mysqld_safe 不允许 mysql 用户在白名单目录外新建日志文件，这里预创建
# ---------------------------------------------------------------------------
COPY docker/my.cnf      /etc/my.cnf
COPY docker/nginx.conf  /etc/nginx/nginx.conf
RUN rm -f /etc/nginx/conf.d/default.conf
# 修复「玩家后台」tab 页（原版 wd.zip 里的 index.php 有两个问题）：
#   1) iframe 用 ./cp、./pay 这类不带尾斜杠的目录 URL，nginx 会 301 到内部端口 8081，
#      而 8081 未对外发布，浏览器连不上 → 切换 tab 白屏；
#   2) 页面残留门户模板的 new Swiper(...) 初始化，但既没引 swiper.min.js、
#      页面也没有 .content / .swiper-container 结构 → 控制台 ReferenceError。
# 用修好的页面覆盖，避免重建镜像时又从 wd.zip 解压回原始版本。
COPY docker/gm-index.php /www/wwwroot/game/gm/index.php
RUN chmod 777 /www/wwwroot/game/gm/index.php
# 物品发放清单：原版 item.txt 只有 125 个常用物品，用客户端 ItemInfo.luac 里
# 的 2139 个物品名补齐（去重、过滤会破坏 HTML / 邮件格式的特殊字符）。
# 同时给 gm.php / index2.php 的物品下拉加 lay-search，否则 2000+ 项无法检索。
COPY docker/gm-item.txt   /www/wwwroot/game/gm/item.txt
COPY docker/gm-gm.php     /www/wwwroot/game/gm/gm.php
COPY docker/gm-index2.php /www/wwwroot/game/gm/index2.php
RUN chmod 777 /www/wwwroot/game/gm/item.txt /www/wwwroot/game/gm/gm.php /www/wwwroot/game/gm/index2.php
COPY docker/www.conf    /etc/php-fpm.d/www.conf
COPY docker/redis.conf  /etc/redis.conf
COPY docker/start-services.sh docker/entrypoint.sh docker/loadsql.sh docker/adapt.sh /wd/
RUN chmod +x /wd/*.sh && mkdir -p /wd/logs /wd/redis6/data /var/run/mysqld && \
    touch /wd/logs/mysqld.log /wd/logs/mysqld_init.log && \
    chown -R mysql:mysql /wd/logs /var/run/mysqld

# 教程里 MySQL root 密码（loadsql / config.php 硬编码了这个值）
ENV MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

EXPOSE 81 83 88 9877 3306 6379 10001 10201

WORKDIR /wd
ENTRYPOINT ["/wd/entrypoint.sh"]
CMD ["/wd/start-services.sh"]
