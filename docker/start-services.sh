#!/bin/bash
# Lightweight process supervision (replaces supervisor to avoid EPEL archive repos).
# Starts mysql / redis / php-fpm / nginx, restarting any that exit.
# Then (AUTO_START_GAME=1) starts the game services following the original
# tutorial order, but waits until aaa is really listening on 10001 before
# launching the gs game lines (gs depends on aaa to hand out the server list).
cd /wd
mkdir -p logs /var/run/mysqld
chown -R mysql:mysql logs /var/run/mysqld
touch logs/mysqld.log; chown mysql:mysql logs/mysqld.log 2>/dev/null

MPASS="${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}"

run_forever() {
    local name="$1"; shift
    while true; do
        "$@" >>"/wd/logs/$name.log" 2>&1
        echo "$(date '+%F %T') $name exited ($?), restart in 3s" >> /wd/logs/supervisor.log
        sleep 3
    done
}

# NOTE: MySQL 5.6 has no '--daemonize' option (that is 5.7+), so mysqld_safe is used.
run_forever mysqld  /usr/bin/mysqld_safe --user=mysql &
run_forever redis   /wd/redis6/bin/redis-server /etc/redis.conf --daemonize no &
run_forever php-fpm /usr/sbin/php-fpm -F &
run_forever nginx   /usr/sbin/nginx -g 'daemon off;' &

# ---------- game services ----------
if [ "${AUTO_START_GAME:-0}" = "1" ]; then
    (
        # wait for MySQL and Redis
        for i in $(seq 1 90); do
            mysqladmin --socket=/var/lib/mysql/mysql.sock -u root -p"$MPASS" ping >/dev/null 2>&1 && break
            sleep 2
        done
        for i in $(seq 1 20); do
            /wd/redis6/bin/redis-cli ping >/dev/null 2>&1 && break
            sleep 1
        done
        echo "$(date '+%F %T') MySQL/Redis ready, starting game services" >> /wd/logs/game.log

        # infrastructure first (no gs yet)
        for s in aaa dba ldba csa ccs dps msa mss ps sns spa tts; do
            ( cd /home/s1/$s && exec sh ./run$s ) >>/wd/logs/game_$s.log 2>&1 &
            sleep 1
        done

        # wait until aaa really listens on 10001 (gs needs it for the server list)
        for i in $(seq 1 90); do
            if cat /proc/net/tcp 2>/dev/null | awk 'NR>1{split($2,a,":");if(strtonum("0x"a[2])==10001 && $4=="0A")print 1}' | head -1 | grep -q 1; then
                echo "$(date '+%F %T') aaa ready on 10001, starting gs lines" >> /wd/logs/game.log
                break
            fi
            sleep 2
        done
        sleep 3

        # gs game lines
        for n in "" 2 3 4 5 6 7 8 9 10; do
            ( cd /home/s1/gs && exec sh ./rungs$n ) >>/wd/logs/game_rungs$n.log 2>&1 &
            sleep 1
        done
        echo "$(date '+%F %T') all game services started" >> /wd/logs/game.log
    ) >/wd/logs/qd.log 2>&1 &

    # ruoyi admin backend
    (
        for i in $(seq 1 30); do
            mysqladmin --socket=/var/lib/mysql/mysql.sock -u root -p"$MPASS" ping >/dev/null 2>&1 && break
            sleep 2
        done
        cd /home/daili && exec sh ry.sh start
    ) >/wd/logs/ry.log 2>&1 &
fi

wait
