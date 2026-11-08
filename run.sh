#!/usr/bin/env bash
# 一键运行（等价 make run）
set -e
cd "$(dirname "$0")"

if docker ps -a --format '{{.Names}}' | grep -qx 'wd-server'; then
    echo "容器 wd-server 已存在，先删除"
    docker rm -f wd-server
fi

docker volume create wd-mysql-data >/dev/null 2>&1 || true

exec docker run -d --name wd-server \
  --restart unless-stopped --shm-size=1g \
  -v wd-mysql-data:/var/lib/mysql \
  -p 81:81 -p 80:80 -p 443:443 -p 88:88 -p 9877:9877 -p 3306:3306 -p 6379:6379 \
  -p 10001-10310:10001-10310 \
  wd-server:latest
