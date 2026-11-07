#!/bin/bash
# wd-mobile-docker container entrypoint
#   1) First run: init MySQL, set root password, import 11 databases, create plugin account
#   2) Then hand to supervisord (mysqld/redis/php-fpm/nginx)
#   3) AUTO_START_GAME=1: also launch game processes & proxy in background
set -u

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}"
CLIENT_IP="${CLIENT_IP:-172.29.220.175}"
DATADIR=/var/lib/mysql
SOCK=/var/lib/mysql/mysql.sock
LOGDIR=/wd/logs
mkdir -p "$DATADIR" "$LOGDIR" /var/run/mysqld
chown -R mysql:mysql "$DATADIR" "$LOGDIR" /var/run/mysqld
touch "$LOGDIR/mysqld_init.log" "$LOGDIR/mysqld.log" 2>/dev/null
chown mysql:mysql "$LOGDIR/mysqld_init.log" "$LOGDIR/mysqld.log" 2>/dev/null

log() { echo "[entrypoint] $(date '+%F %T') $*"; }

# ---------- start temporary mysqld for initialization ----------
if [ ! -d "$DATADIR/mysql" ]; then
    log "init MySQL data dir (mysql_install_db)"
    /usr/bin/mysql_install_db --user=mysql --datadir="$DATADIR" >"$LOGDIR/mysql_install.log" 2>&1
fi

log "start temporary mysqld (init)"
/usr/bin/mysqld_safe --user=mysql --datadir="$DATADIR" --socket="$SOCK" \
    --skip-networking --log-error="$LOGDIR/mysqld_init.log" &
INIT_PID=$!

# wait until mysqld can actually execute SQL. Probe with BOTH no-password and
# with-password root: on first init root has no password yet, but after a restart
# the root password is already set, so a no-password-only probe would fail forever.
probe_ready() {
    mysql --socket="$SOCK" -u root -e "SELECT 1" >/dev/null 2>&1 && return 0
    mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1 && return 0
    return 1
}
ready=0
for i in $(seq 1 120); do
    if probe_ready; then
        ready=1; break
    fi
    sleep 1
done
if [ "$ready" != "1" ]; then
    log "ERROR: mysqld not ready in 120s, see $LOGDIR/mysqld_init.log"
    exit 1
fi

if [ ! -f /wd/.db_initialized ]; then
    log "first run: set root password -> import databases -> create plugin account"
    mysqladmin --socket="$SOCK" -u root password "$MYSQL_ROOT_PASSWORD" 2>/dev/null \
        || log "root password already set (skip)"
    # import must succeed; retry, and exit on repeated failure (never run degraded)
    ok=0
    for attempt in 1 2 3; do
        if MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" /wd/loadsql.sh; then
            ok=1; break
        fi
        log "loadsql failed (attempt $attempt), retry in 5s..."
        sleep 5
    done
    if [ "$ok" != "1" ]; then
        log "ERROR: database import failed repeatedly, exit"
        exit 1
    fi
    touch /wd/.db_initialized
    mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" <<SQL
GRANT ALL PRIVILEGES ON *.* TO 'W1G=1LA*3'@'%' IDENTIFIED BY 'Hrr1dkVU8S@W1G=LA*3HwMsqtrUZWQ72n' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    log "plugin DB account W1G=1LA*3 created (@'%', for Windows plugin on 3306)"
else
    log "database already initialized, skip import"
fi

# ---------- data-layer adaptation (must run while temp mysqld is alive) ----------
# fix release_adb.server game-line address, create gddb, gen TLS cert, etc.
/wd/adapt.sh

log "shutdown temporary mysqld"
mysqladmin --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" shutdown >/dev/null 2>&1 \
    || kill "$INIT_PID" 2>/dev/null
wait "$INIT_PID" 2>/dev/null

# ---------- optional: auto-start game ----------
if [ "${AUTO_START_GAME:-0}" = "1" ]; then
    log "AUTO_START_GAME=1 -> launching game (qd) and proxy (ry.sh)"
    nohup /home/s1/qd >"$LOGDIR/qd.log" 2>&1 &
    (cd /home/daili && nohup sh ry.sh start >"$LOGDIR/ry.log" 2>&1)
fi

log "hand over to supervisord: $*"
exec "$@"
