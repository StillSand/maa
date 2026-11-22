# maa

> 基于 [Lyxot/maa-template](https://github.com/Lyxot/maa-template) 魔改：用 GitHub Actions 跑 MAA（明日方舟）日常，支持加密快照备份、Cloudflare Tunnel 远程控制和 SSH 调试。

> 使用前请先读「安全说明」。账号数据一旦泄露，后果自负。

## 运行模式

workflow 只有一个输入 `mode`：

| mode | 恢复快照 | 等待手动设置 | 运行 MAA 日常 | 用途 |
| --- | --- | --- | --- | --- |
| `auto` | 是 | 否 | 是 | 日常定时运行 |
| `update` | 是 | 是 | 否 | 游戏更新或重新登录后，保存新快照 |
| `init` | 否（用默认镜像） | 是 | 否 | 首次从零初始化 |

手动模式（`init` / `update`）在环境准备好后会停下来，最多等 60 分钟：

1. 浏览器打开隧道域名，输入用户名和密码
2. 点击 `H264 Converter` 进入画面
3. 登录游戏，按下面的「游戏内设置」调好
4. 在 SSH 终端执行 `create_flag`
5. workflow 继续导出容器并上传新快照

## 游戏内设置

- 只下载基础资源，不下载语音包
- 低画质、30 帧
- 关闭「退出基建提示」
- 进剿灭页面，关掉剿灭的新手提示

### 卡在进入游戏

MAA 的日志会记录每个任务的开始和结束（`StartUp Start` / `StartUp Completed`），监控直接基于这个：

- 单个任务超过 `MAA_TASK_TIMEOUT`（默认 3 小时）仍未完成：检查设备是否在线，在线就停止游戏并重新拉起 MAA（最多 `MAA_MAX_RESTARTS` 次，默认 1）
- 等待期间检测到游戏正在下载资源（数据目录或网卡接收量持续增长）：下载结束（连续 3 分钟无增长）后提前重启
- 没有任务在跑、且超过 `MAA_TIMEOUT`（默认 2 小时）没有新日志：判定为卡死，直接失败

重启用的是同一个 `daily.toml`，第二次运行仍然会执行完整日常。

## 使用方法

1. Fork 本仓库，或者 Use this template 创建新仓库
2. 修改 `.github/workflows/maa.yml` 顶部的 `CLIENT_TYPE`（`Official` / `Bilibili`）
3. 在 `Settings` → `Secrets and variables` → `Actions` 中添加 Secrets：

| 名称 | 必填 | 说明 |
| --- | --- | --- |
| `CONTAINER_ENCRYPTION_KEY` | 是 | 快照加密密钥，随便填一段足够长的字符串。丢失后旧快照无法恢复 |
| `CLOUDFLARE_TUNNEL_TOKEN` | 是 | Cloudflare Tunnel Token。隧道里创建一个 Public Hostname，Service 选 `HTTP`、URL 填 `localhost:8000` |
| `WS_SCRCPY_PASSWORD` | 是 | 远程控制页面的密码。不填则出于安全考虑不启动远程控制页 |
| `WS_SCRCPY_USER` | 否 | 远程控制页面的用户名，默认 `maa`。和密码一样以 Secret 保存 |
| `TELEGRAM_BOT_TOKEN` | 否 | Telegram 通知，找 [@BotFather](https://t.me/BotFather) 创建 |
| `TELEGRAM_CHAT_ID` | 否 | Telegram Chat ID，找 [@userinfobot](https://t.me/userinfobot) 获取 |

Variables 只有一个 `SEND_MSG`（`true` / `false`）。Variables 是**明文公开**的，不要往里放任何密钥。

4. 进入 Actions → MAA → Run workflow，`mode` 选 `init`
5. 等待日志出现 `等待手动设置`（首次约 10 分钟），打开隧道域名，用 `WS_SCRCPY_USER` / `WS_SCRCPY_PASSWORD` 登录
6. 完成游戏内设置后，在 SSH 里执行 `create_flag`，等待 workflow 结束
7. 结束后会生成 `snapshot-YYYYMMDD-HHMM` 的 Release，后续运行会自动恢复它
8. 日常使用 `mode=auto`，或者启用定时任务

### 定时运行

`.github/workflows/maa.yml` 里的 `schedule` 默认是注释掉的，取消注释即可：

```yaml
schedule:
  - cron: '0 5,17 * * *'   # UTC，对应北京时间 13:00 和 01:00
```

定时任务通常不会准点，一般会晚 5~20 分钟。也可以用自己的调度器触发 `workflow_dispatch`。

## SSH 调试

tmate 的公共服务已于 2025 年 7 月永久关停，本项目改用 [upterm](https://github.com/owenthereal/upterm)。

- 连接命令会出现在运行页的 Step Summary 里，同时上传为 artifact `ssh-command`（保留 1 天）
- 只有触发者（仓库所有者）在 GitHub 上登记的 SSH 公钥可以连接，拿到命令也进不去
- job 的步骤结束后，会话还会再保留 60 分钟，方便失败后排查
- 如果网络封了 22 端口，用 WebSocket 通道：

```bash
upterm join wss://<ID>@uptermd.upterm.dev
```

或者保留普通 ssh 客户端：

```bash
ssh -o ProxyCommand='upterm proxy wss://<ID>@uptermd.upterm.dev' <ID>@uptermd.upterm.dev:443
```

## 远程控制与密码

ws-scrcpy 本身没有任何认证能力（官方明确 "There is no authorization on any level."），因此部署结构是：

```
浏览器 → Cloudflare Tunnel → nginx (Basic Auth) → ws-scrcpy
```

- 打开页面时弹出浏览器原生的用户名 / 密码框，认证通过才进入页面
- 用户名来自 Secret `WS_SCRCPY_USER`，密码来自 Secret `WS_SCRCPY_PASSWORD`
- ws-scrcpy 不对外发布端口，只存在于 Docker 内网
- 未设置 `WS_SCRCPY_PASSWORD` 时不会启动远程控制页，只启动隧道
- Cloudflare 后台的 Service 仍然指向 `localhost:8000`，加了密码之后不需要改动

## 快照与恢复

- 每次运行成功后导出容器镜像和数据目录，压缩加密后分卷上传为 Release
- 默认保留最近 2 份快照，恢复时取最新的
- 单份约 13~14G，导出、压缩、上传合计约 15 分钟
- 失败时不会覆盖旧快照；如果启动失败，可以手动恢复上一份
- `CONTAINER_ENCRYPTION_KEY` 丢失后，所有快照都无法解密

## 安全说明：哪些是公开的

当仓库是 public 时：

| 内容 | 可见性 |
| --- | --- |
| 代码、commit、workflow 文件 | 公开 |
| Actions 运行状态、日志、Step Summary | 公开 |
| Secrets 的值 | 不可见，日志里显示为 `***` |
| Variables 的值 | 公开 |
| 快照内容 | 加密 |
| 隧道域名 | 不在仓库和日志里，取决于是否外传 |
| SSH 会话地址 | 日志里可见，但只有触发者的公钥能连 |

建议：

- 远程控制页单独使用一个密码，不要复用游戏、邮箱等其他账号的密码
- 不要把 `CONTAINER_ENCRYPTION_KEY` 写进任何 commit 或 issue
- 不要在公开场合贴隧道域名；需要更强保护时，可以在 Cloudflare 上加 Access 策略
- 不要把其他人加为仓库 collaborator，否则对方可以读取 Secrets

## 注意事项

1. 账号数据以加密形式存储在 GitHub Release 中，但 GitHub 侧仍能看到密文和运行日志，请自行评估风险
2. 游戏会自动更新，配置好后一般不用管；如果超过 7 天没有运行，或者在其他设备上清理了游戏会话，需要重新执行一次 `mode=update` 并登录
3. 建议使用公开仓库：私有仓库的 Actions 有额度限制，公开仓库的 runner 性能也更好
4. 定时任务不会准点触发，通常延后 5~20 分钟
5. 远程控制依赖 Cloudflare Tunnel；没有隧道就只能跑 MAA，无法手动登录
6. Telegram 通知是可选的，不配置也能正常跑
7. 修改 token、URL 等隐私数据时，确保放在 Secrets 里，且不会出现在任何 commit 中