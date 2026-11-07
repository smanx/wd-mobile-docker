#!/bin/bash
# wd-server 容器运行体检脚本（宿主机执行）
C=${1:-wd-server}
pass=0; fail=0
ok()  { echo "  [OK]   $*"; pass=$((pass+1)); }
bad() { echo "  [DOWN] $*"; fail=$((fail+1)); }
ex() { docker exec "$C" bash -c "$1" 2>/dev/null; }

echo "== 容器状态 =="
docker ps --filter name="$C" --format '{{.Names}}  {{.Status}}' | grep -q . \
    && ok "容器运行中" || { bad "容器未运行"; exit 1; }

echo "== 等待初始化完成 =="
for i in 1 2 3 4 5 6 8 10 12 14 16 18 20 22 24; do
    docker logs "$C" 2>&1 | grep -q "移交 supervisord" && break
    sleep 5
done

echo "== 基础服务 =="
ex "mysqladmin -uroot -pj4Tj3vq1ih6 ping" | grep -q alive && ok "MySQL 5.6" || bad "MySQL"
ex "/wd/redis6/bin/redis-cli ping" | grep -q PONG && ok "Redis 6.2" || bad "Redis"
R=$(ex "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81/reg.html")
[ "$R" = "200" ] && ok "Nginx:81 (注册页 200)" || bad "Nginx:81 (HTTP=$R)"
R=$(ex "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81/yz.php")
echo "$R" | grep -qE '200|302' && ok "PHP-FPM (yz.php $R)" || bad "PHP-FPM (HTTP=$R)"
R=$(ex "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9877/")
echo "$R" | grep -qE '200|301|302|401' && ok "若依API:9877 ($R)" || bad "若依API:9877 (HTTP=$R)"
R=$(ex "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:88/")
echo "$R" | grep -qE '200|301|302' && ok "代理后台:88 ($R)" || echo "  [WARN] 代理后台:88 HTTP=$R（需先 sh /home/daili/ry.sh start）"

echo "== 数据库 =="
N=$(ex "mysql -uroot -pj4Tj3vq1ih6 -N -e 'SHOW DATABASES'" | grep -cE '^(release_|account$|wdgm$)')
[ "$N" = "11" ] && ok "11 个业务库齐全" || bad "业务库=$N (期望11)"

echo "== 游戏进程 =="
P=$(ex "pgrep -c magic_s1" | tail -1)
if [ "${P:-0}" -ge 1 ]; then
    ok "magic_s1 游戏进程 x$P"
    ex "tail -1 /home/s1/aaa/Startup.log"
else
    echo "  [--] 游戏进程未启动（正常，默认手动启动）"
fi
J=$(ex "pgrep -cf ruoyi-admin-encrypted.jar" | tail -1)
[ "${J:-0}" -ge 1 ] && ok "若依 jar 运行中" || echo "  [--] 若依 jar 未启动（sh /home/daili/ry.sh start 可启动）"

echo "== 资源 =="
docker stats --no-stream --format "  {{.Name}}  内存 {{.MemUsage}}  CPU {{.CPUPerc}}" "$C" 2>/dev/null

echo
echo "===== 体检结果: OK=$pass DOWN=$fail ====="
