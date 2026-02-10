"""
MAA 报告处理脚本
负责读取 MAA 运行结果，格式化并分发到不同的输出渠道
"""
import os
import time
from format_summary import format_for_github, format_for_telegram

def read_maa_output():
    """读取 MAA 运行输出"""
    # 读取摘要
    try:
        with open('msg', 'r') as f:
            summary = f.read().strip("\n")
    except FileNotFoundError:
        summary = ""
    
    # 读取时间信息
    try:
        with open('time_info', 'r') as f:
            time_lines = f.read().strip().split('\n')
            start_time = time_lines[0] if len(time_lines) > 0 else "未知"
            end_time = time_lines[1] if len(time_lines) > 1 else "未知"
            duration = time_lines[2] if len(time_lines) > 2 else "未知"
    except FileNotFoundError:
        start_time = "未知"
        end_time = "未知"
        duration = "未知"
    
    return {
        'summary': summary,
        'start_time': start_time,
        'end_time': end_time,
        'duration': duration
    }

def generate_github_summary(data):
    """生成 GitHub Actions Summary"""
    github_step_summary = os.getenv('GITHUB_STEP_SUMMARY')
    if not github_step_summary:
        print("ℹ️  GITHUB_STEP_SUMMARY 环境变量未设置，跳过 GitHub Summary 生成")
        return False
    
    # 检测是否经过了自动修复
    was_fixed = os.getenv('WAS_FIXED', 'false').lower() == 'true'
    
    # 提取日期部分（YYYY-MM-DD）
    start_date = data['start_time'].split()[0] if data['start_time'] != "未知" else None
    
    with open(github_step_summary, 'w', encoding='utf-8') as f:
        if was_fixed:
            f.write("# 🎮 MAA 执行报告（经过自动修复）\n\n")
            f.write("> ⚠️ **注意：** 本次执行经过了一次自动修复（游戏资源更新），总耗时较长\n\n")
        else:
            f.write("# 🎮 MAA 执行报告\n\n")
        if start_date:
            f.write(f"**📅 执行日期:** {start_date}\n\n")
        f.write("---\n\n")
        
        # 显示完整的 Summary 部分
        if data['summary']:
            f.write("## 📊 任务执行详情\n\n")
            f.write(format_for_github(data['summary'], start_date))
        else:
            f.write("*无报告信息*\n\n")
        
        f.write("\n---\n\n")
        f.write(f"🕐 **开始:** {data['start_time']} | 🏁 **结束:** {data['end_time']} | ⏱️ **耗时:** {data['duration']}\n")
    
    print("✅ GitHub Summary 已生成")
    return True

def generate_telegram_message(data):
    """生成 Telegram 消息内容并保存"""
    # 检查是否需要发送 Telegram 消息
    send_msg = os.getenv('SEND_MSG', 'false').lower()
    telegram_bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
    telegram_chat_id = os.getenv('TELEGRAM_CHAT_ID')
    
    if send_msg != 'true':
        print("ℹ️  SEND_MSG 未启用，跳过 Telegram 消息生成")
        return False
    
    if not telegram_bot_token or not telegram_chat_id:
        print("⚠️  TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID 未配置，跳过 Telegram 消息生成")
        return False
    
    # 检测是否经过了自动修复
    was_fixed = os.getenv('WAS_FIXED', 'false').lower() == 'true'
    
    # 提取日期部分（YYYY-MM-DD）
    start_date = data['start_time'].split()[0] if data['start_time'] != "未知" else None
    formatted_summary = format_for_telegram(data['summary'], start_date)

    # 构建消息标题
    if was_fixed:
        title = "🎮 MAA 自动化执行报告（经过自动修复）"
        fix_notice = "\n⚠️ <b>注意：</b>本次执行经过了一次自动修复（游戏资源更新），总耗时较长\n"
    else:
        title = "🎮 MAA 自动化执行报告"
        fix_notice = ""

    # 构建消息
    message = f"""{title}{fix_notice}

📅 <b>执行日期:</b> {start_date if start_date else '未知'}

🕐 <b>开始:</b> {data['start_time']} | 🏁 <b>结束:</b> {data['end_time']} | ⏱️ <b>耗时:</b> {data['duration']}

📊 <b>任务详情:</b>

<pre>
{formatted_summary}
</pre>
"""
    
    # 保存到文件供 send_msg.py 使用
    with open('telegram_msg.txt', 'w', encoding='utf-8') as f:
        f.write(message)
    
    print("✅ Telegram 消息已生成")
    return True

def main():
    """主函数"""
    print("📊 开始处理 MAA 报告...")
    
    # 读取 MAA 输出
    data = read_maa_output()
    
    if not data['summary']:
        print("⚠️ 警告：未找到 MAA 摘要信息")
    
    # 生成 GitHub Summary（总是生成，因为这是 GitHub Actions 的功能）
    github_generated = generate_github_summary(data)
    
    # 生成 Telegram 消息（根据环境变量决定）
    telegram_generated = generate_telegram_message(data)
    
    # 总结
    print("\n" + "="*50)
    print("📊 报告处理完成")
    print(f"  GitHub Summary: {'✅ 已生成' if github_generated else '⏭️  已跳过'}")
    print(f"  Telegram 消息: {'✅ 已生成' if telegram_generated else '⏭️  已跳过'}")
    print("="*50)

if __name__ == "__main__":
    main()
