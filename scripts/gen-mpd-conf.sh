#!/usr/bin/env bash
#
# 动态生成 /etc/mpd.conf
#
# 输出通道分三类，用户在网页上自由切换（同时只开一路，避免多路同时出声）：
#   1. 每一块 ALSA 声卡各一条（HDMI0 / HDMI1 / 3.5mm 等，自动探测）
#   2. 蓝牙音箱（bluealsa A2DP）
#   3. HTTP 音频流（浏览器用当前访问的设备播放）
#
set -euo pipefail

OUT="${1:-/etc/mpd.conf}"
MUSIC_DIR="${MUSIC_DIR:-/music}"
DEFAULT_CARD="${DEFAULT_CARD:-Headphones}"
ENABLE_BT="${ENABLE_BLUETOOTH:-yes}"
BT_MAC="${BT_MAC:-}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# 探测声卡：card 号 | 声卡名 | device 号
mapfile -t CARDS < <(aplay -l 2>/dev/null \
    | sed -n 's/^card \([0-9]*\): [^ ]* \[\([^]]*\)\], device \([0-9]*\):.*/\1|\2|\3/p')

# 挑一条作为默认启用的通道：先按 DEFAULT_CARD 关键字匹配，匹配不到就用第一块
chosen=""
for c in "${CARDS[@]}"; do
    IFS='|' read -r card name dev <<< "$c"
    if echo "${name} hw:${card},${dev}" | grep -qi -- "$DEFAULT_CARD"; then
        chosen="${card}|${dev}"
        break
    fi
done
if [ -z "$chosen" ] && [ "${#CARDS[@]}" -gt 0 ]; then
    IFS='|' read -r card name dev <<< "${CARDS[0]}"
    chosen="${card}|${dev}"
fi

{
cat <<EOF
music_directory     "${MUSIC_DIR}"
playlist_directory  "/var/lib/mpd/playlists"
db_file             "/var/lib/mpd/tag_cache"
log_file            "/dev/stdout"
pid_file            "/run/mpd/pid"
state_file          "/var/lib/mpd/state"

user                "root"
bind_to_address     "any"
port                "6600"

follow_outside_symlinks "yes"
follow_inside_symlinks  "yes"

input {
        plugin "curl"
}
EOF

for c in "${CARDS[@]}"; do
    IFS='|' read -r card name dev <<< "$c"
    hw="hw:${card},${dev}"
    if [ "$chosen" = "${card}|${dev}" ]; then en=yes; else en=no; fi
    cat <<EOF

# 声卡输出：${name}
audio_output {
        type            "alsa"
        name            "${name}"
        device          "${hw}"
        mixer_type      "software"
        enabled         "${en}"
}
EOF
done

if [ "$ENABLE_BT" = yes ]; then
    if [ -n "$BT_MAC" ]; then
        btdev="bluealsa:DEV=${BT_MAC},PROFILE=a2dp"
    else
        btdev="bluealsa"
    fi
    cat <<EOF

# 蓝牙音箱：需先在宿主机完成配对（未配对此通道不会出声）
audio_output {
        type            "alsa"
        name            "蓝牙音箱 A2DP"
        device          "${btdev}"
        format          "44100:16:2"
        mixer_type      "software"
        enabled         "no"
}
EOF
fi

cat <<EOF

# 浏览器本机播放：MPD HTTP 流，经 nginx 8000 端口代理出去
audio_output {
        type            "httpd"
        name            "浏览器本机播放"
        encoder         "vorbis"
        port            "8001"
        format          "44100:16:2"
        always_on       "yes"
        enabled         "yes"
}
EOF
} > "$OUT"

n="$(grep -c '^audio_output' "$OUT" || true)"
echo "[gen-mpd-conf] 已写入 ${OUT}，共 ${n} 条输出通道"
for c in "${CARDS[@]}"; do
    IFS='|' read -r card name dev <<< "$c"
    printf '[gen-mpd-conf]   声卡 hw:%s,%s  ->  %s\n' "$card" "$dev" "$name"
done
