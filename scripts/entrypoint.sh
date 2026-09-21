#!/usr/bin/env bash
#
# 容器入口：生成 MPD 配置 -> 生成登录口令 -> 交给 supervisord
#
set -euo pipefail

WEB_USER="${WEB_USER:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-}"

# ---------- 1. 生成 MPD 配置（自动探测声卡 / 蓝牙 / HTTP 流）----------
/opt/music/scripts/gen-mpd-conf.sh /etc/mpd.conf

# ---------- 2. 网页登录口令 ----------
if [ -z "$WEB_PASSWORD" ]; then
    WEB_PASSWORD="$(head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 10)"
    cat <<EOF

======================================================
 未设置 WEB_PASSWORD，已为你生成随机登录口令：
    用户名：${WEB_USER}
    密码：  ${WEB_PASSWORD}
 请记下来；下次部署可通过环境变量固定。
======================================================

EOF
fi
printf '%s:%s\n' "$WEB_USER" "$(openssl passwd -apr1 "$WEB_PASSWORD")" > /etc/nginx/.htpasswd
chmod 600 /etc/nginx/.htpasswd

# ---------- 3. 让 myMPD 监听所有网卡 ----------
if [ -f /etc/mympd/mympd.conf ]; then
    sed -i 's|"http_host"[[:space:]]*:[[:space:]]*"[^"]*"|"http_host": "0.0.0.0"|' \
        /etc/mympd/mympd.conf 2>/dev/null || true
fi

# ---------- 4. 目录与权限 ----------
mkdir -p /var/lib/mpd/playlists /var/log/mpd /run/mpd /var/lib/mympd /var/log/supervisor
chown -R mpd:audio /var/lib/mpd /var/log/mpd /run/mpd 2>/dev/null || true

exec "$@"
