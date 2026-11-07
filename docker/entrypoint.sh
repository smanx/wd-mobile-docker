#!/bin/bash
# wd-mobile-docker 容器入口�?#   1) 首次运行初始�?MySQL（装�?�?设密�?�?导入 11 个数据库 �?创建插件账号�?#   2) 之后交给 supervisord 管理 mysqld/redis/php-fpm/nginx
#   3) AUTO_START_GAME=1 时顺带后台拉起游戏进程与代理（默认不拉，13GB 内存�?set -u

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}"
DATADIR=/var/lib/mysql
SOCK=/var/lib/mysql/mysql.sock
LOGDIR=/wd/logs
mkdir -p "$DATADIR" "$LOGDIR" /var/run/mysqld
chown -R mysql:mysql "$DATADIR" "$LOGDIR" /var/run/mysqld
touch "$LOGDIR/mysqld_init.log" "$LOGDIR/mysqld.log" 2>/dev/null; chown mysql:mysql "$LOGDIR/mysqld_init.log" "$LOGDIR/mysqld.log" 2>/dev/null

log() { echo "[entrypoint] $(date '+%F %T') $*"; }

# ---------- 临时启动 mysqld 用于初始�?----------
if [ ! -d "$DATADIR/mysql" ]; then
    log "初始�?MySQL 数据目录 (mysql_install_db)"
    /usr/bin/mysql_install_db --user=mysql --datadir="$DATADIR" >"$LOGDIR/mysql_install.log" 2>&1
fi

log "启动临时 mysqld (初始化用)"
/usr/bin/mysqld_safe --user=mysql --datadir="$DATADIR" --socket="$SOCK" \
    --skip-networking --log-error="$LOGDIR/mysqld_init.log" &
INIT_PID=$!

for i in $(seq 1 60); do
    mysqladmin --socket="$SOCK" -u root ping >/dev/null 2>&1 && break
    sleep 1
    if [ "$i" -eq 60 ]; then
        log "错误：mysqld 60 秒内未就绪，�?$LOGDIR/mysqld_init.log"
        exit 1
    fi
done

if [ ! -f /wd/.db_initialized ]; then
    log "首次运行：设�?root 密码 �?导入数据�?�?创建插件账号"
    mysqladmin --socket="$SOCK" -u root password "$MYSQL_ROOT_PASSWORD" 2>/dev/null \
        || log "root 密码已存在（跳过设置�?
    /wd/loadsql.sh && touch /wd/.db_initialized
    mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" <<SQL
GRANT ALL PRIVILEGES ON *.* TO 'W1G=1LA*3'@'%' IDENTIFIED BY 'Hrr1dkVU8S@W1G=LA*3HwMsqtrUZWQ72n' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    log "插件数据库账�?W1G=1LA*3 已创建（@'%'，供 Windows 插件�?3306 用）"
else
    log "数据库已初始化过，跳过导�?
fi

# ---- 数据层适配（必须在临时 mysqld 存活期间执行�?---
# �?release_adb.server 游戏服下发地址、补 gddb 库等。放在关闭临�?mysqld 之前�?/wd/adapt.sh

log "关闭临时 mysqld"
mysqladmin --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" shutdown >/dev/null 2>&1 \
    || kill "$INIT_PID" 2>/dev/null
wait "$INIT_PID" 2>/dev/null

# ---------- 可选：自动拉起游戏 ----------
if [ "${AUTO_START_GAME:-0}" = "1" ]; then
    log "AUTO_START_GAME=1 �?后台启动游戏进程 (qd) 与代�?(ry.sh)"
    nohup /home/s1/qd >"$LOGDIR/qd.log" 2>&1 &
    (cd /home/daili && nohup sh ry.sh start >"$LOGDIR/ry.log" 2>&1)
fi

log "移交 supervisord: $*"
exec "$@"
