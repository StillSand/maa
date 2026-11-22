#!/bin/bash
# Telegram 消息发送脚本

TELEGRAM_BOT_TOKEN="$1"
TELEGRAM_CHAT_ID="$2"
MESSAGE="$3"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "! Telegram 未配置，跳过消息发送"
    exit 0
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MESSAGE}" \
    -d parse_mode="HTML" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ 消息已发送到 Telegram"
else
    echo "✗ Telegram 消息发送失败"
fi
