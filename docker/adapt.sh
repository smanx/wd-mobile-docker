#!/bin/bash
# entrypoint 运行时适配（幂等）：
# 1) 覆盖 jar 内数据库密码（Spring Boot 外部配置）
# 2) 建 90sdk 最小库（若依主数据源）
# 3) 生成 TLS 自签证书（81/443 分流的 https 后端用）
# 4) 删除 nginx 包自带的 default.conf（listen 80 会与 stream 分流冲突）
# 注意：mcrypt 需在镜像里装好（Dockerfile php-mcrypt），此处只做配置层适配
set -u

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-j4Tj3vq1ih6}"
SOCK=/var/lib/mysql/mysql.sock
# 客户端（模拟器/手机）可访问的本机地址，游戏服下发地址用这个
CLIENT_IP="${CLIENT_IP:-172.29.220.175}"

# ---- 若依适配 ----
cd /home/daili
if [ -f ruoyi-admin-encrypted.jar ]; then
    unzip -p ruoyi-admin-encrypted.jar BOOT-INF/classes/application-druid.yml > application-druid.yml 2>/dev/null
    sed -i "s/QQ24460571/$MYSQL_ROOT_PASSWORD/g" application-druid.yml
fi

mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" <<'SQL' 2>/dev/null
CREATE DATABASE IF NOT EXISTS 90sdk DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
USE 90sdk;
CREATE TABLE IF NOT EXISTS sys_config (
  config_id INT NOT NULL AUTO_INCREMENT, config_name VARCHAR(100) DEFAULT '', config_key VARCHAR(100) DEFAULT '',
  config_value VARCHAR(500) DEFAULT '', config_type CHAR(1) DEFAULT 'N', create_by VARCHAR(64) DEFAULT '',
  create_time DATETIME NULL, update_by VARCHAR(64) DEFAULT '', update_time DATETIME NULL, remark VARCHAR(500) NULL,
  PRIMARY KEY (config_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
INSERT IGNORE INTO sys_config VALUES
 (1,'主框架页-默认皮肤样式名称','sys.index.skinName','skin-blue','Y','admin',NOW(),'',NULL,''),
 (2,'用户管理-账号自助-是否开启','sys.account.captchaEnabled','true','Y','admin',NOW(),'',NULL,''),
 (3,'用户管理-账号自助-是否开启注册','sys.account.registerUser','false','Y','admin',NOW(),'',NULL,'');
CREATE TABLE IF NOT EXISTS sys_user (
  user_id BIGINT NOT NULL AUTO_INCREMENT, dept_id BIGINT NULL, user_name VARCHAR(30) NOT NULL, nick_name VARCHAR(30) NOT NULL,
  user_type VARCHAR(2) DEFAULT '00', email VARCHAR(50) DEFAULT '', phonenumber VARCHAR(11) DEFAULT '', sex CHAR(1) DEFAULT '0',
  avatar VARCHAR(100) DEFAULT '', password VARCHAR(100) DEFAULT '', status CHAR(1) DEFAULT '0', del_flag CHAR(1) DEFAULT '0',
  login_ip VARCHAR(128) DEFAULT '', login_date DATETIME NULL, create_by VARCHAR(64) DEFAULT '', create_time DATETIME NULL,
  update_by VARCHAR(64) DEFAULT '', update_time DATETIME NULL, remark VARCHAR(500) NULL,
  PRIMARY KEY (user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
INSERT IGNORE INTO sys_user VALUES
 (1,NULL,'admin','若依','00','ry@163.com','15888888888','1','',
  '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2','0','0','127.0.0.1',NOW(),'admin',NOW(),'',NULL,'管理员');
CREATE TABLE IF NOT EXISTS sys_logininfor (
  info_id BIGINT NOT NULL AUTO_INCREMENT, user_name VARCHAR(50) DEFAULT '', ipaddr VARCHAR(128) DEFAULT '',
  login_location VARCHAR(255) DEFAULT '', browser VARCHAR(50) DEFAULT '', os VARCHAR(50) DEFAULT '',
  status CHAR(1) DEFAULT '0', msg VARCHAR(255) DEFAULT '', login_time DATETIME NULL,
  PRIMARY KEY (info_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
SQL
log() { echo "[entrypoint] $(date '+%F %T') $*"; }
log "若依适配完成（外部 druid 配置 + 90sdk 最小库）"

# ---- 预置测试账号 admin1/admin1（避免每次重建都要手动注册）----
# SDK 登录(/login/index.php -> api.php verify) 查 account.account 表。
# 密码算法: strtoupper(md5(account + strtoupper(md5(pass)) + "xiaowu2023"))
for i in $(seq 1 60); do
    mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1 && break
    sleep 1
done
PWD5=$(printf 'admin1' | md5sum | awk '{print toupper($1)}')
FINAL=$(printf 'admin1%sxiaowu2023' "$PWD5" | md5sum | awk '{print toupper($1)}')
mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" account 2>/dev/null <<SQL && log "预置账号 admin1/admin1 完成"
INSERT INTO account (account,password,ip,time,agent,money,pass)
VALUES ('admin1','$FINAL','127.0.0.1',NOW(),'xiaowu','0','admin1')
ON DUPLICATE KEY UPDATE password=VALUES(password),pass=VALUES(pass);
SQL

# ---- 游戏服下发地址：必须是【客户端可达】地址，不能是 127.0.0.1 ----
# 关键：release_adb.server 的 ip/outer_ip 是 aaa 下发给【客户端】去连接 gs 游戏线的地址
# （不是服务端内部互联——内部互联靠 gs 的 [Me] Name 匹配，不依赖本表 ip）。
# 若为 127.0.0.1，客户端会连自己的回环 → "连接服务器超时"。
# 必须设为客户端/模拟器可达的地址（CLIENT_IP）。
for i in $(seq 1 60); do
    mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1 && break
    sleep 1
done
if mysql --socket="$SOCK" -u root -p"$MYSQL_ROOT_PASSWORD" \
    -e "UPDATE release_adb.server SET ip='127.0.0.1', outer_ip='$CLIENT_IP'" 2>/dev/null; then
    log "release_adb.server 游戏线下发地址 → $CLIENT_IP"
fi
# 注意：不要创建 gddb/gsdb 等短名库。原包 loadsql 导入的库即可让 aaa/gs 正常工作；
# 额外建库反而会干扰 aaa 的架构探测（Unknown database 告警）。

# ---- 客户端选服地址 dist.lua ----
# 客户端登录后从 patch.zip 的 patch/dist.lua 读取区服 aaa 地址，再去连该地址进大区。
# 原包是原打包者服务器 IP（死地址），必须改成客户端可达地址 CLIENT_IP。
if [ -f /www/wwwroot/game/atm/g-bits/patch.zip ]; then
    if ! command -v zip >/dev/null 2>&1; then
        (yum install -y -q zip >/dev/null 2>&1) || true
    fi
    rm -rf /tmp/wdpatch && mkdir -p /tmp/wdpatch && cd /tmp/wdpatch
    unzip -o -q /www/wwwroot/game/atm/g-bits/patch.zip 2>/dev/null
    if [ -f patch/dist.lua ]; then
        # 把 aaa 的地址统一改为 CLIENT_IP:10001（客户端选服连接地址）
        sed -i -E "s#aaa = \"[0-9.]+:[0-9]+\"#aaa = \"$CLIENT_IP:10001\"#g" patch/dist.lua
        sed -i -E "s#ftpHost = \"[0-9.]+\"#ftpHost = \"$CLIENT_IP\"#g" patch/dist.lua
        rm -f /www/wwwroot/game/atm/g-bits/patch.zip
        zip -q -r /www/wwwroot/game/atm/g-bits/patch.zip . 2>/dev/null
        log "dist.lua 区服地址 → $CLIENT_IP:10001"
    fi
    cd /wd
fi

# ---- TLS 证书（容器每次重建后 /etc 会重置，这里保证证书存在）----
if [ ! -f /etc/nginx/ssl/wd.crt ]; then
    mkdir -p /etc/nginx/ssl
    cat > /tmp/ssl.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = $CLIENT_IP
[v3_req]
subjectAltName = @alt
[alt]
IP.1 = $CLIENT_IP
IP.2 = 172.29.220.75
IP.3 = 172.29.220.175
DNS.1 = static.leiting1.com
DNS.2 = login.leiting1.com
DNS.3 = loginali.leiting1.com
DNS.4 = loginsjhl.leiting1.com
DNS.5 = member.leiting1.com
DNS.6 = pay.leiting1.com
DNS.7 = payali.leiting1.com
DNS.8 = paysjhl.leiting1.com
DNS.9 = logmonitor.leiting1.com
DNS.10 = testlogin.leiting1.com
DNS.11 = testmember.leiting1.com
DNS.12 = testpay.leiting1.com
DNS.13 = testlogmonitor.leiting1.com
DNS.14 = testkernel.leiting1.com
DNS.15 = webproxy.leiting1.com
DNS.16 = helper.leiting1.com
DNS.17 = www.leiting1.com
EOF
    openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/ssl/wd.key \
        -out /etc/nginx/ssl/wd.crt -days 3650 -nodes -config /tmp/ssl.cnf 2>/dev/null
    log "TLS 自签证书已生成（含 SDK 域名 SAN）"
fi

# ---- 删除 nginx 包自带 default.conf（listen 80 与 stream 分流冲突）----
if [ -f /etc/nginx/conf.d/default.conf ] && [ ! -f /etc/nginx/conf.d/default.conf.bak ]; then
    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    log "已移除 nginx 默认 default.conf（避免 listen 80 冲突）"
fi

cd /wd
