#!/bin/bash
# 轻量进程看护（替代 supervisor，避免 EPEL 归档源风险）
# 拉起 mysql / redis / php-fpm / nginx，任一退出 3 秒后重启。
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

wait
