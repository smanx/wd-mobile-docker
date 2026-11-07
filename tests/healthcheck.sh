#!/bin/bash
# 全面体检：服务、游戏、关键配置、持久化风险
C=wd-server
echo "===== 1. 容器与进程 ====="
docker ps --filter name=$C --format '{{.Status}}'
docker exec $C bash -c "echo 'magic_s1: ' \$(pgrep -c magic_s1); echo 'mysql: ' \$(mysqladmin -uroot -pj4Tj3vq1ih6 ping 2>/dev/null); echo 'redis: ' \$(/wd/redis6/bin/redis-cli ping 2>/dev/null)"
echo
echo "===== 2. 端口监听 ====="
docker exec $C bash -c "cat /proc/net/tcp | awk 'NR>1 && \$4==\"0A\"{print \$2}' | awk -F: '{print strtonum(\"0x\"\$2)}' | sort -un | tr '\n' ' '" ; echo
echo
echo "===== 3. HTTP/TLS 服务 ====="
for u in "http://127.0.0.1:81/reg.html" "https://127.0.0.1:81/reg.html" "http://127.0.0.1:88/" "https://127.0.0.1:443/reg.html"; do
  code=$(docker exec $C bash -c "curl -sk -o /dev/null -w '%{http_code}' --max-time 4 $u")
  echo "$u = $code"
done
echo
echo "===== 4. 关键数据配置（进程重启会丢吗？存哪）====="
docker exec $C bash -c "echo 'server表IP: ' \$(mysql -uroot -pj4Tj3vq1ih6 -N -e 'SELECT DISTINCT ip FROM release_adb.server' 2>/dev/null)"
docker exec $C bash -c "echo 'account: ' \$(mysql -uroot -pj4Tj3vq1ih6 -N -e 'SELECT account FROM account.account' 2>/dev/null | tr '\n' ' ')"
docker exec $C bash -c "echo 'gddb存在: ' \$(mysql -uroot -pj4Tj3vq1ih6 -N -e \"SHOW DATABASES LIKE 'gddb'\" 2>/dev/null)"
echo
echo "===== 5. 持久化检查（mysql 数据在 volume 吗）====="
docker inspect $C --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
echo
echo "===== 6. mcrypt / 证书 ====="
docker exec $C bash -c "echo 'mcrypt: ' \$(php -m | grep -ci mcrypt); ls /etc/nginx/ssl/wd.crt 2>/dev/null && echo '证书: 存在' || echo '证书: 缺失'"
