#!/bin/bash
# 导入 11 个数据库（对应教程 /home/s1/sql/loadsql）。
# 原脚本有两处变量笔误导致 account/wdgm 从未被 drop，这里按正确逻辑重写：
#   全部 DROP → CREATE(utf8) → 导入(--default-character-set=latin1，与原教程一致)
set -eu
[ -n "${MYSQL_ROOT_PASSWORD:-}" ] || { echo "need MYSQL_ROOT_PASSWORD"; exit 1; }

SQLDIR=/home/s1/sql
SOCK=/var/lib/mysql/mysql.sock
MYSQL="mysql --socket=$SOCK -u root -p${MYSQL_ROOT_PASSWORD}"

DBS=(release_adb release_ddb release_gddb release_gsdb release_ldb
     release_mdb release_sdb release_sldb release_tdb account wdgm)

echo "[loadsql] drop + create databases"
for db in "${DBS[@]}"; do
    $MYSQL -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
done

echo "[loadsql] importing (latin1)"
for db in "${DBS[@]}"; do
    printf '  %-14s ' "$db"
    $MYSQL --default-character-set=latin1 "$db" < "$SQLDIR/$db.sql"
    echo "ok"
done

echo "[loadsql] 全部导入完成"
