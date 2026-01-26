# maa-template

## 使用方法
***如果你担心账号泄露，不要使用！有关账号泄露的问题概不负责，详见注意事项1***
1. Use this template 创建新仓库 (或者 fork 这个仓库)
2. 修改`.github/workflows/maa.yml`的 [L23](https://github.com/Lyxot/maa-template/blob/main/.github/workflows/maa.yml#L23)、[L25](https://github.com/Lyxot/maa-template/blob/main/.github/workflows/maa.yml#L25)
    | 参数 | 描述 | 选项 |
    | --- | --- | --- |
    | `CLIENT_TYPE` | 客户端版本 | `Official` `Bilibili` |
    | `SEND_MSG` | 是否在运行结束后发送简报到QQ | `true` `false`  |
3. 在仓库的`Settings`-`Secrets and variables`-`Actions`-`Repository secrets`中创建 secret
    | 变量 | 描述 | 说明 | 示例 |
    | --- | --- | --- | --- |
    | `FRPC_TOKEN` | Sakura Frp 的 Token | 到 [Sakura Frp](https://www.natfrp.com/) 申请一个隧道，节点选择海外节点，本地端口8000 | `xxxxxxxxxxxxxxxx:xxxxxx` |
    | `ONEBOT_URL` | [OneBot](https://github.com/botuniverse/onebot-11/blob/master/communication/http.md) 的 http 地址 | `SEND_MSG`为`false`时不需要，选一个支持 OneBot11 协议的QQ机器人，比如 [NapCatQQ](https://github.com/NapNeko/NapCatQQ)，开启 http 服务器 | `http://xxx.xxx.xxx.xxx:5700` |
    | `QQID` | QQ号 | 接收简报的QQ号，`SEND_MSG`为`false`时不需要 | |
4. 进入仓库的 Actions，选择 MAA，点击 Run workflow，勾选`Update manually`，点击 Run workflow
5. 运行到`Setup Debug Session`时，在 log 中找到 runner 的 ssh 连接地址，ssh 连接到 runner，按 q 进入终端
6. 运行到`Manual update`时，浏览器连接到 frp 隧道，点击 `H264 Converter` 进行远程控制
7. 打开游戏，下载选择基础资源，不下载语音包，登录账号，设置低画质30帧，关掉退出基建提示，进剿灭页面关掉剿灭的提示
8. 在 ssh 终端中执行 `create_flag && exit`，等待 workflow 运行完毕
9. 修改`.config/maa/tasks/daily.toml`，[配置文档](https://github.com/MaaAssistantArknights/maa-cli/blob/main/crates/maa-cli/docs/zh-CN/config.md)，不会改就使用示例即可
10. 进入 Actions，选择 MAA，点击 Run workflow，勾选`Run`，点击 Run workflow
11. 同步骤6，观察 MAA 是否正常运行
12. 修改`.github/workflows/maa.yml`的 [L18](https://github.com/Lyxot/maa-template/blob/main/.github/workflows/maa.yml#L18) 来配置定时运行，按照UTC时区配置，示例中的为每天4点和16点运行
13. 给这个仓库点个 star
14. 快乐自动化

## 注意事项
1. 账号数据存储在 Github Actions 的 Cache 中，通常情况下其他人不能访问数据，请不要将其他人添加为仓库的合作者，也不要修改这个 workflow 的触发方式，以防账号泄露
2. 游戏会自动更新，配置好后就不需要管了，除非在其它设备上执行了清理会话，或者超过7天没有运行 workflow，需要重新执行步骤4 到步骤8
3. 建议仓库设置为公开仓库，私有仓库的 Actions 有限制，普通用户每月只有 2000 分钟的额度，超出后无法使用 Actions，另外公开仓库的 runner 为 4核 16G，私有仓库为 2核 7G，在私有仓库运行可能导致游戏崩溃
4. 定时任务不会准时运行，通常在配置时间的 5~20 分钟后开始运行
5. 要使用内网穿透才能登录游戏，示例中使用了 Sakura Frp，有能力的自己改
6. 示例中使用 OneBot11 接口给 QQ 发送简报，不需要的可以将`SEND_MSG`配置为`false`，有能力的可以自己改
7. 如果你自己修改了注意事项 5 或 6，确保你的 token、url 等隐私数据存储在 secrets 中，且无法在任何 commit 中找到其明文
