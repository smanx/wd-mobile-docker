#!/bin/bash
# Lightweight process supervision (replaces supervisor to avoid EPEL archive repos).
# Starts mysql / redis / php-fpm / nginx, restarting any that exit.
# Then always starts the game services following the original tutorial order,
# but waits until aaa is really listening on 10001 before launching the gs game
# lines (gs depends on aaa to hand out the server list).
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

# ---------- game services (always started) ----------
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

        # A magic_s1 service's first bind can transiently fail ("Bind is failed")
        # while other services are starting. Generic helper: start a service and
        # wait until its game port really listens; retry up to 5 times.
        #   start_svc <dir> <script> <port|0>
        start_svc() {
            local dir="$1" script="$2" port="$3" attempt i
            for attempt in 1 2 3 4 5; do
                ( cd /home/s1/$dir && exec sh ./$script ) >>/wd/logs/game_$script.log 2>&1 &
                if [ "$port" = "0" ]; then sleep 3; return 0; fi
                for i in $(seq 1 45); do
                    if cat /proc/net/tcp 2>/dev/null | awk -v P="$port" 'NR>1{split($2,a,":");if(strtonum("0x"a[2])==P && $4=="0A")print 1}' | head -1 | grep -q 1; then
                        echo "$(date '+%F %T') $dir ready on $port (attempt $attempt)" >> /wd/logs/game.log
                        return 0
                    fi
                    sleep 2
                done
                echo "$(date '+%F %T') $dir not ready (attempt $attempt), killing and retrying" >> /wd/logs/game.log
                pkill -9 -f "start_${dir}" 2>/dev/null || true
                sleep 8
            done
            echo "$(date '+%F %T') $dir FAILED after 5 attempts, continuing" >> /wd/logs/game.log
        }

        # dependency order: aaa -> dba/ldba -> csa -> ccs -> (gs lines) -> helpers
        start_svc aaa runaaa 10001
        start_svc dba rundba 10004
        start_svc ldba runldba 10006
        start_svc csa runcsa 10003
        start_svc ccs runccs 10002

        # gs game lines (aaa/dba/ldba/csa/ccs are all ready now)
        for n in "" 2 3 4 5 6 7 8 9 10; do
            ( cd /home/s1/gs && exec sh ./rungs$n ) >>/wd/logs/game_rungs$n.log 2>&1 &
            sleep 1
        done

        # helper services (no fixed game ports to probe)
        for s in dps msa mss ps sns spa tts; do
            start_svc $s run$s 0
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

wait
