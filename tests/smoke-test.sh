#!/bin/bash
# wd-mobile-docker 冒烟测试：验证镜像内服务与游戏二进制可用�?# 用法: ./smoke-test.sh  （在 WSL/宿主机执行，需已构�?wd-server:latest�?set -u
NAME=wd-test
IMG=wd-server:latest
PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

ex() { docker exec "$NAME" bash -c "$1" 2>/dev/null; }

echo "== 1. 启动容器 =="
docker rm -f "$NAME" >/dev/null 2>&1
docker run -d --name "$NAME" --memory=10g --memory-swap=10g \
    -p 127.0.0.1:18081:81 "$IMG" >/dev/null || { echo "容器启动失败"; exit 1; }
ok "容器已启�?

echo "== 2. 等待初始化（首次导库�?1-2 分钟�?=="
for i in $(seq 1 60); do
    docker logs "$NAME" 2>&1 | grep -q "移交 supervisord" && break
    sleep 5
done
docker logs "$NAME" 2>&1 | grep -E "\[entrypoint\]|loadsql" | tail -6
docker logs "$NAME" 2>&1 | grep -q "全部导入完成" && ok "数据库导入完�? || bad "未见导入完成标记"
sleep 5

echo "== 3. 基础服务 =="
ex "mysqladmin -uroot -pj4Tj3vq1ih6 ping" | grep -q alive \
    && ok "MySQL 存活" || bad "MySQL 未响�?
ex "/wd/redis6/bin/redis-cli ping" | grep -q PONG \
    && ok "Redis 6.2 PONG" || bad "Redis 未响�?
R=$(ex "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81/reg.html")
echo "$R" | grep -q 200 && ok "Nginx:81 reg.html 200" || bad "Nginx:81 HTTP=$R"
R=$(ex "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81/yz.php")
echo "$R" | grep -qE '200|302' && ok "PHP-FPM yz.php HTTP=$R" || bad "PHP 不工�?HTTP=$R"

echo "== 4. 数据库导入检�?=="
N=$(ex "mysql -uroot -pj4Tj3vq1ih6 -N -e 'SHOW DATABASES'" | grep -cE '^(release_|account$|wdgm$)')
[ "$N" = "11" ] && ok "11 个业务库齐全" || bad "业务库数�?$N (期望 11)"
CNT=$(ex "mysql -uroot -pj4Tj3vq1ih6 -N -e 'SELECT COUNT(*) FROM account.account'" | grep -v Warning)
[ -n "$CNT" ] && ok "account.account 可查�?(rows=$CNT)" || bad "account 表查询失�?
U=$(ex "mysql -uroot -pj4Tj3vq1ih6 -N -e \"SELECT user FROM mysql.user WHERE user='W1G=1LA*3'\"" | grep -v Warning)
[ -n "$U" ] && ok "插件账号 W1G=1LA*3 存在" || bad "插件账号缺失"

echo "== 5. 游戏二进制依赖（32�?loader 实测�?=="
LOADER=$(ex "test -e /lib/ld-linux.so.2 && echo yes || echo no")
[ "$LOADER" = "yes" ] && ok "/lib/ld-linux.so.2 存在" || bad "32�?loader 缺失"
ex "/lib/ld-linux.so.2 --list /home/s1/aaa/magic_s1 2>&1 | grep -c 'not found'" > /tmp/nf.txt
NF=$(tail -1 /tmp/nf.txt)
[ "$NF" = "0" ] && ok "magic_s1 全部依赖可解�? || bad "�?$NF 个依赖缺�?

echo "== 6. 游戏进程启动测试（aaa 认证服） =="
docker exec -d "$NAME" bash -c "cd /home/s1/aaa && ./runaaa > /tmp/runaaa.out 2>&1"
sleep 12
P=$(ex "pgrep -c magic_s1" | tail -1)
if [ "${P:-0}" -ge 1 ]; then
    ok "magic_s1(aaa) 进程存活 (count=$P)"
    LAST=$(ex "tail -1 /home/s1/aaa/Startup.log")
    echo "    Startup.log: $LAST"
    echo "$LAST" | grep -q "$(date +%Y)" && ok "aaa 本次启动完成（新日志�? || echo "    [warn] 未见本次启动日志"
else
    bad "magic_s1 未存�?
    echo "    runaaa 输出: $(ex "cat /tmp/runaaa.out 2>/dev/null" | head -2)"
fi
ex "/home/s1/stop" >/dev/null 2>&1

echo "== 7. 代理后台(若依 jar)启动测试 =="
docker exec -d "$NAME" bash -c "cd /home/daili && sh ry.sh start > /tmp/ry.out 2>&1"
sleep 25
J=$(ex "pgrep -cf ruoyi-admin-encrypted.jar" | tail -1)
[ "${J:-0}" -ge 1 ] && ok "若依 jar 进程存活" || bad "若依 jar 未存�?
R=$(ex "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9877/")
echo "$R" | grep -qE '200|301|302|401' && ok "若依 API 端口 9877 响应 HTTP=$R" || echo "    [warn] 9877 HTTP=$R（首次启动慢，可忽略�?
ex "sh /home/daili/ry.sh stop" >/dev/null 2>&1

echo "== 8. 资源占用 =="
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" "$NAME" 2>/dev/null

echo
echo "===== 结果: PASS=$PASS FAIL=$FAIL ====="
[ "$FAIL" = "0" ]
