FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        mpd mpc mympd \
        alsa-utils \
        bluez bluealsa libasound2-plugin-bluez \
        sox \
        supervisor nginx openssl \
        ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

RUN mkdir -p /var/lib/mpd/playlists /var/log/mpd /run/mpd \
             /var/lib/mympd /music /var/log/supervisor

COPY conf/supervisord.conf /etc/supervisor/conf.d/music.conf
COPY conf/nginx.conf       /etc/nginx/conf.d/default.conf
COPY scripts/              /opt/music/scripts/
RUN chmod +x /opt/music/scripts/*.sh

# 内置测试音：没有任何音乐文件时，也能用它验证每一路输出是否真正出声
RUN sox -n -r 44100 -c 2 /music/00-test-tone-440Hz.wav synth 15 sine 440 vol 0.3

EXPOSE 80 8000

ENTRYPOINT ["/opt/music/scripts/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
