#!/bin/bash
# 轻量进程看护（替代 supervisor，避免 EPEL 归档源风险）
# 拉起 mysql / redis / php-fpm / nginx，任一退出 3 秒后重启。
# 然后（若 AUTO_START_GAME=1）等 MySQL/Redis 就绪后，按原教程启动游戏：
#   cd /home/s1 && ./qd
cd /wd
mkdir -p logs /var/run/mysqld
chown -R mysql:mysql logs /var/run/mysqld
touch logs/mysqld.log; chown mysql:mysql logs/mysqld.log 2>/dev/null

run_forever() {
    local name="$1"; shift
    while true; do
        "$@" >>"logs/$name.log" 2>&1
        echo "$(date '+%F %T') $name exited ($?), restart in 3s" >> logs/supervisor.log
        sleep 3
    done
}

run_forever mysqld  /usr/bin/mysqld_safe --user=mysql &
run_forever redis   /wd/redis6/bin/redis-server /etc/redis.conf --daemonize no &
run_forever php-fpm /usr/sbin/php-fpm -F &
run_forever nginx   /usr/sbin/nginx -g 'daemon off;' &

# ---------- 游戏启动（严格按原教程：cd /home/s1 && ./qd）----------
# gs 游戏线依赖 aaa/ccs/dba/ldba 等服务由 qd 一次性按正确顺序拉起；
# 且这些服务要连 MySQL，所以必须等 mysqld/redis 就绪后再跑 qd。
# 不要自己 nohup 单个进程或改 cwd，否则 gs 会卡在
# "Try to obtain game_server_list" / "Missing config(telnet_port)"。
if [ "${AUTO_START_GAME:-0}" = "1" ]; then
    (
        # 等 MySQL 能接受连接
        for i in $(seq 1 60); do
            mysqladmin --socket=/var/lib/mysql/mysql.sock -u root -p"${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}" ping >/dev/null 2>&1 && break
            sleep 2
        done
        # 等 Redis 就绪
        for i in $(seq 1 20); do
            /wd/redis6/bin/redis-cli ping >/dev/null 2>&1 && break
            sleep 1
        done
        echo "$(date '+%F %T') MySQL/Redis ready, starting game: cd /home/s1 && ./qd" >> logs/game.log
        cd /home/s1 && exec sh ./qd
    ) >logs/qd.log 2>&1 &

    # 代理后台（若依），就绪后启动
    (
        for i in $(seq 1 30); do
            mysqladmin --socket=/var/lib/mysql/mysql.sock -u root -p"${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}" ping >/dev/null 2>&1 && break
            sleep 2
        done
        cd /home/daili && exec sh ry.sh start
    ) >logs/ry.log 2>&1 &
fi

wait
