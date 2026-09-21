FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

# ---------- 1. Debian 官方包 ----------
# 注意两个坑：
#   a) mympd 不在 Debian 官方源里（packages.debian.org 全套件搜索零结果），必须单独装（见第 2 步）
#   b) 蓝牙守护进程包不叫 bluealsa，叫 bluez-alsa-utils；而且它不能装进容器 ——
#      会和宿主机的 bluealsa 抢 D-Bus 上的 org.bluealsa 名字。
#      容器里只需要 ALSA 插件 libasound2-plugin-bluez，
#      它通过挂载进来的 /var/run/dbus 去找宿主机上的 bluealsa 守护进程。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mpd mpc \
        alsa-utils libasound2-plugin-bluez \
        sox \
        supervisor nginx openssl \
        ca-certificates curl gnupg tzdata; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /etc/nginx/sites-enabled/default

# ---------- 2. myMPD ----------
# myMPD 从未被 Debian 官方源收录（packages.debian.org 全套件搜索零结果），
# 只能从作者维护的 openSUSE OBS 仓库取。
# 关键顺序：必须先「配置 OBS 仓库 + apt-get update」，再安装。
#   - 用 trusted=yes 绕过 OBS 历史上过期过的 GPG 密钥（2025-02 那次导致大批用户 apt update 失败）。
#   - 先 update 是为了让 mympd 的全部依赖都能从 OBS 索引里解析到（直接 dpkg -i .deb 时缺依赖可 apt -f 修复）。
# 安装分两步：优先直连下载对应架构的 .deb 本地装（最快、不依赖索引解析）；
#             直连失败再退回 apt-get install mympd（索引已在上面 update 过，依赖齐全）。
# 仓库名按基础镜像的 VERSION_ID 自动匹配（bookworm=12 -> Debian_12，trixie=13 -> Debian_13）。
RUN set -eux; \
    . /etc/os-release; \
    ARCH="$(dpkg --print-architecture)"; \
    REPO="https://download.opensuse.org/repositories/home:/jcorporation/Debian_${VERSION_ID}"; \
    echo "deb [trusted=yes] ${REPO}/ ./" > /etc/apt/sources.list.d/mympd.list; \
    apt-get update; \
    DEB="$(curl -fsSL "${REPO}/${ARCH}/" \
          | grep -oE "mympd_[0-9.]+-[0-9]+_${ARCH}\.deb" | sort -V | tail -1)"; \
    if [ -n "$DEB" ] && curl -fsSL -o /tmp/mympd.deb "${REPO}/${ARCH}/${DEB}"; then \
        echo "[info] 直连下载 ${DEB}"; \
        dpkg -i /tmp/mympd.deb || apt-get install -f -y --no-install-recommends; \
    else \
        echo "[warn] 直连下载失败，退回 OBS apt 仓库安装"; \
        apt-get install -y --no-install-recommends mympd; \
    fi; \
    command -v mympd; \
    rm -f /tmp/mympd.deb /etc/apt/sources.list.d/mympd.list; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/mpd/playlists /var/log/mpd /run/mpd \
             /var/lib/mympd /var/cache/mympd /music /var/log/supervisor

COPY conf/supervisord.conf /etc/supervisor/conf.d/music.conf
COPY conf/nginx.conf       /etc/nginx/conf.d/default.conf
COPY scripts/              /opt/music/scripts/
RUN chmod +x /opt/music/scripts/*.sh

# 内置测试音：没有任何音乐文件时，也能用它验证每一路输出是否真正出声。
# 注意：不能直接放 /music —— 用户挂载音乐目录后会被遮蔽，所以放 /opt，
#       由 entrypoint 在启动时软链/复制进实际的音乐目录。
RUN mkdir -p /opt/music/testtone \
 && sox -n -r 44100 -c 2 /opt/music/testtone/00-test-tone-440Hz.wav synth 15 sine 440 vol 0.3

EXPOSE 80 8000

ENTRYPOINT ["/opt/music/scripts/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
