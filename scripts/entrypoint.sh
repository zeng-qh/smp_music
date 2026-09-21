#!/usr/bin/env bash
#
# 容器入口：生成 MPD 配置 -> 配置 myMPD -> 生成登录口令 -> 交给 supervisord
#
set -euo pipefail

WEB_USER="${WEB_USER:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-}"
MUSIC_DIR="${MUSIC_DIR:-/music}"
MYMPD_PORT=8080          # myMPD 内部端口，由 nginx 80 端口反代
MYMPD_CONF_DIR=/var/lib/mympd/config

# ---------- 1. 生成 MPD 配置（自动探测声卡 / 蓝牙 / HTTP 流）----------
/opt/music/scripts/gen-mpd-conf.sh /etc/mpd.conf

# ---------- 2. myMPD 配置 ----------
# 两个必须处理的点：
#   a) myMPD 默认监听 80，会和 nginx 抢端口 -> 改到 8080，由 nginx 反代
#   b) 默认 ssl = true 会走 HTTPS，nginx 用 http 反代会失败 -> 关掉
# v8.0.0 起 mympd.conf 被废弃，配置是 /var/lib/mympd/config/ 下的纯文本文件（文件名=键，内容=值）
mkdir -p "$MYMPD_CONF_DIR" /var/cache/mympd /var/lib/mympd

set_conf() { printf '%s\n' "$2" > "${MYMPD_CONF_DIR}/$1"; }

set_conf http_host "0.0.0.0"
set_conf http_port "${MYMPD_PORT}"
set_conf ssl       "false"
set_conf mpd_host  "127.0.0.1"
set_conf mpd_port  "6600"

# 老版本（< v8）仍读 /etc/mympd/mympd.conf，一并处理
if [ -f /etc/mympd/mympd.conf ]; then
    sed -i -E \
        -e 's|^[[:space:]]*http_port.*|http_port = '"${MYMPD_PORT}"'|' \
        -e 's|^[[:space:]]*http_host.*|http_host = 0.0.0.0|' \
        -e 's|^[[:space:]]*ssl[[:space:]]*=.*|ssl = false|' \
        -e 's|^[[:space:]]*mpd_host.*|mpd_host = 127.0.0.1|' \
        /etc/mympd/mympd.conf 2>/dev/null || true
fi

echo "[entrypoint] myMPD 版本: $(mympd -v 2>/dev/null || echo '未知')"
echo "[entrypoint] myMPD 监听 127.0.0.1:${MYMPD_PORT}，nginx 在 80 端口做登录鉴权后反代"

# ---------- 3. 网页登录口令 ----------
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

# ---------- 4. 内置测试音 ----------
# /music 通常被宿主机目录挂载覆盖，镜像里预置的文件会看不见，
# 所以放 /opt，启动时再软链（退化为复制）进实际音乐目录。
TONE="00-test-tone-440Hz.wav"
SRC="/opt/music/testtone/${TONE}"
if [ -f "$SRC" ] && [ ! -e "${MUSIC_DIR}/${TONE}" ]; then
    if ln -s "$SRC" "${MUSIC_DIR}/${TONE}" 2>/dev/null; then
        echo "[entrypoint] 测试音已软链到 ${MUSIC_DIR}/${TONE}"
    elif cp "$SRC" "${MUSIC_DIR}/${TONE}" 2>/dev/null; then
        echo "[entrypoint] 测试音已复制到 ${MUSIC_DIR}/${TONE}"
    else
        echo "[entrypoint] 警告：音乐目录不可写，测试音未放入（不影响已有音乐播放）"
    fi
fi
# MPD 需要允许跟随音乐目录内的软链
if ! grep -q 'follow_inside_symlinks' /etc/mpd.conf; then
    printf 'follow_inside_symlinks  "yes"\nfollow_outside_symlinks "yes"\n' >> /etc/mpd.conf
fi

# ---------- 5. 目录与权限 ----------
mkdir -p /var/lib/mpd/playlists /var/log/mpd /run/mpd /var/log/supervisor
chown -R mpd:audio /var/lib/mpd /var/log/mpd /run/mpd 2>/dev/null || true

exec "$@"
