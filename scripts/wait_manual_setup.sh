#!/bin/bash
# 等待手动设置完成脚本

TELEGRAM_BOT_TOKEN="$1"
TELEGRAM_CHAT_ID="$2"

echo "等待手动设置游戏..."

# 发送操作指引到 Telegram
MESSAGE="<b>准备登录游戏</b>

✓ <b>容器和游戏已安装完成！</b>

<b>接下来请按以下步骤操作：</b>

<b>步骤 1：访问远程控制界面</b>
打开浏览器，访问你配置的 Cloudflare Tunnel 域名

<b>步骤 2：进入远程控制</b>
点击页面上的 <code>H264 Converter</code> 按钮
你会看到 Android 模拟器界面

<b>步骤 3：登录游戏</b>
打开明日方舟游戏
下载<b>基础资源</b>（不要下载语音包）
登录你的游戏账号

<b>步骤 4：游戏设置</b>
进入游戏设置：
  • 画质：<b>低画质</b>
  • 帧率：<b>30 帧</b>
  • 关闭「退出基建提示」
进入剿灭页面，关掉剿灭的新手提示

<b>步骤 5：完成设置</b>
回到 SSH 终端，执行命令：
<code>create_flag && exit</code>

<b>超时时间：</b>60 分钟

<b>提示：</b>完成后系统会自动保存容器状态"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" > /dev/null 2>&1

echo "i 操作指引已发送到 Telegram"
echo "i 请在 SSH 终端执行: create_flag && exit"

# 等待标志文件
while true; do
    if [[ -f ~/flag_update_completed ]]; then
        # 发送完成通知
        COMPLETE_MSG="✓ <b>手动设置已完成</b>

游戏登录和设置已完成！

<b>接下来：</b>
系统将自动保存容器状态，请稍候...

完成后你将收到最终报告"

        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="${COMPLETE_MSG}" \
            -d parse_mode="HTML" > /dev/null 2>&1
        
        echo "✓ 手动设置已完成"
        break
    fi
    sleep 1
done
