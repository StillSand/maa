#!/bin/bash
# SSH 信息发送脚本

TELEGRAM_BOT_TOKEN="$1"
TELEGRAM_CHAT_ID="$2"

echo "发送 SSH 连接信息到 Telegram..."

# 等待 tmate 启动并生成日志
sleep 10

# 尝试多种方式获取 SSH 连接信息
TMATE_SSH=""

# 方法 1: 从环境变量获取
if [ -n "$TMATE_SSH" ]; then
    TMATE_SSH="$TMATE_SSH"
# 方法 2: 从 tmate 日志文件获取
elif [ -f ~/.tmate/socket.log ]; then
    TMATE_SSH=$(grep -oP 'ssh session: \K.*' ~/.tmate/socket.log 2>/dev/null | head -1)
# 方法 3: 从 /tmp 目录查找
elif [ -f /tmp/tmate.log ]; then
    TMATE_SSH=$(grep -oP 'ssh \K.*' /tmp/tmate.log 2>/dev/null | head -1)
fi

# 如果还是没有获取到，尝试从进程信息获取
if [ -z "$TMATE_SSH" ]; then
    # 等待更长时间
    sleep 10
    # 再次尝试
    TMATE_SSH=$(grep -oP 'ssh session: \K.*' ~/.tmate/socket.log 2>/dev/null | head -1)
fi

# 如果仍然没有，使用提示信息
if [ -z "$TMATE_SSH" ]; then
    TMATE_SSH="SSH 连接信息正在生成中，请稍候并查看 GitHub Actions 日志"
fi

# 构建消息
MESSAGE="<b>SSH 调试会话已启动</b>

<b>SSH 连接命令：</b>
<code>${TMATE_SSH}</code>

<b>操作步骤：</b>
1复制上面的 SSH 命令
2在你的电脑终端执行该命令
3连接成功后按 <code>q</code> 键进入终端
4保持 SSH 连接，等待下一步指示

<b>当前状态：</b>正在安装容器和游戏，请稍候...

<b>安全提示：</b>此连接信息仅发送给你，请勿分享

<b>提示：</b>如果上面没有显示 SSH 命令，请查看 GitHub Actions 日志中的 'Setup Debug Session' 步骤"

# 发送到 Telegram
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" > /dev/null 2>&1

echo "✓ SSH 信息已发送到 Telegram"
echo "i SSH 命令: ${TMATE_SSH}"
