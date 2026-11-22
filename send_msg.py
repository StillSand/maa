import requests
import os

bot_token = os.getenv("TELEGRAM_BOT_TOKEN")
chat_id = os.getenv("TELEGRAM_CHAT_ID")

# 读取预先生成的消息
try:
    with open('telegram_msg.txt', 'r', encoding='utf-8') as f:
        message = f.read()
except FileNotFoundError:
    print("✗ 错误：未找到 telegram_msg.txt 文件")
    print("请先运行 process_report.py 生成消息")
    exit(1)

# 发送消息
url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
data = {
    "chat_id": chat_id,
    "text": message,
    "parse_mode": "HTML"  # 使用 HTML 格式，支持代码块
}

try:
    response = requests.post(url, json=data, timeout=10)
    if response.status_code == 200:
        print("✓ Message sent to Telegram successfully")
    else:
        print(f"✗ Failed to send message: {response.status_code}")
        print(response.text)
except Exception as e:
    print(f"✗ Error sending message: {e}")
