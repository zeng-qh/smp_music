# mpd-web-player

树莓派 / NAS 上的网页音乐播放器。声音从**播放器所在机器**发出，网页只负责遥控。

## 三种播放方式，网页上随时切换

| 方式 | 声音从哪出 | 怎么用 |
|---|---|---|
| **本机声卡** | 树莓派的 3.5mm / HDMI0 / HDMI1 | 网页控制台里启用对应输出通道 |
| **蓝牙音箱** | 已配对的蓝牙音箱（A2DP） | 宿主机完成配对后，启用「蓝牙音箱 A2DP」 |
| **当前访问的设备** | 打开网页的那台手机/电脑 | 浏览器打开 `http://<IP>:8000` |

每一路都是 MPD 的一个 `audio_output`，切换就是开关通道，**不用改配置、不用重启容器**。

组件：`MPD`（播放）+ `myMPD`（网页界面）+ `nginx`（登录鉴权 + 音频流代理）+ `supervisord`（进程管理），全部在一个容器里。

## 端口

| 端口 | 用途 |
|---|---|
| `8080` | 网页控制台（需登录） |
| `8000` | 音频流，浏览器直接打开即用本机出声 |

## 快速开始

```bash
# 1. 准备音乐目录（宿主机路径自己改）
mkdir -p /vol1/docker/music/mpd /vol1/docker/music/mympd

# 2. 改配置
cp .env.example .env   # 没有就新建，见下方「环境变量」

# 3. 启动
docker compose up -d

# 4. 看生成的输出通道和随机口令（没设 WEB_PASSWORD 时）
docker compose logs music | head -40
```

浏览器打开 `http://<树莓派IP>:8080`。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `MUSIC_DIR` | `./music` | 宿主机音乐目录，挂到容器内 `/music` |
| `DEFAULT_CARD` | `Headphones` | 默认启用哪块声卡（按名字关键字匹配）。填 `vc4-hdmi-0` / `vc4-hdmi-1` 可默认走 HDMI |
| `ENABLE_BLUETOOTH` | `yes` | 是否生成蓝牙输出通道 |
| `BT_MAC` | 空 | 蓝牙音箱 MAC；留空则连当前已配对的默认设备 |
| `WEB_USER` | `admin` | 登录用户名 |
| `WEB_PASSWORD` | 空 | 登录密码；**留空会生成随机口令并打印在容器日志里** |
| `WEB_PORT` / `STREAM_PORT` | `8080` / `8000` | 对外端口 |

`.env` 示例：

```env
MUSIC_DIR=/vol1/music
DEFAULT_CARD=Headphones
WEB_USER=admin
WEB_PASSWORD=换成你自己的密码
BT_MAC=
```

## 挂多个音乐目录

`docker-compose.yml` 的 volumes 里照着加即可，MPD 会一并索引：

```yaml
      - /vol1/music/album:/music/album:ro
      - /vol1/music/podcast:/music/podcast:ro
```

## 蓝牙音箱（宿主机要先配对）

蓝牙硬件只能由宿主机接管，容器通过 D-Bus 访问宿主机的 `bluealsa`。在**宿主机**执行一次：

```bash
sudo apt install -y bluez bluealsa
sudo sed -i 's|^BLUEALSA_OPTS=.*|BLUEALSA_OPTS="-p a2dp-source"|' /etc/default/bluealsa
sudo systemctl enable --now bluetooth bluealsa

sudo bluetoothctl
#   power on
#   agent on
#   default-agent
#   scan on              # 把音箱切到配对模式
#   pair   <MAC>
#   trust  <MAC>
#   connect <MAC>
```

配对成功后把 MAC 填进 `.env` 的 `BT_MAC`，`docker compose up -d` 重启，再到网页启用「蓝牙音箱 A2DP」。

飞牛 ARM 版可能缺蓝牙固件（树莓派 4B 需要 `BCM4345C0.hcd`），`bluetoothctl list` 看不到 Controller 时先试 `apt install firmware-brcm80211`。

## 测试音

镜像内置 `/music/00-test-tone-440Hz.wav`（15 秒 440Hz 正弦波）。曲库空的时候用它验证每一路输出是否真的出声：

```bash
docker compose exec music mpc update
docker compose exec music mpc add 00-test-tone
docker compose exec music mpc play
```

## 常用命令

```bash
docker compose exec music mpc outputs        # 列出所有输出通道及编号
docker compose exec music mpc enable 2       # 启用第 2 路
docker compose exec music mpc disable 0      # 关掉第 0 路
docker compose exec music mpc update         # 重新扫描曲库
docker compose logs -f music
```

## 通过 GitHub 构建镜像

```bash
git init && git add . && git commit -m "init"
git remote add origin https://github.com/<用户名>/mpd-web-player.git
git tag v1.0.0
git push -u origin main --tags
```

推送 tag 后 Actions 会自动构建 `linux/amd64` + `linux/arm64` 两份镜像并推到 GHCR。arm64 走 QEMU 模拟，首次约 10~20 分钟。

之后树莓派上把 `docker-compose.yml` 的 `build: .` 换成：

```yaml
    image: ghcr.io/<用户名>/mpd-web-player:latest
```

## 已知限制

- 多路输出**不要同时开**：蓝牙有 100~300ms 延迟，和声卡一起开会形成回声。切换时先关旧的再开新的。
- 蓝牙音箱断连后该通道会失效，重连后需要重新 `enable` 一次。
- 容器内 MPD 以 root 运行，这样能直接读宿主机挂进来的音乐目录，避开 uid/gid 权限问题。
