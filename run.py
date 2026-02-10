import subprocess
import toml
import os
import pathlib
import time
import threading
import sys

# 导入 MAA 工具模块
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from maa_utils import clear_fix_flag

# 检查是否是修复模式运行（如果是修复后的重跑，不清除标志）
if os.getenv('MAA_FIX_MODE') != '1':
    # 正常模式运行，清除修复标志，允许进行一次修复
    clear_fix_flag()

client_type = os.getenv("CLIENT_TYPE")
# 超时时间（秒），默认2小时，可通过环境变量配置
timeout_seconds = int(os.getenv("MAA_TIMEOUT", "7200"))  # 默认 7200 秒 = 2 小时

# 修改配置文件中的客户端类型
config = toml.load(str(pathlib.Path.home())+'/.config/maa/tasks/daily.toml')
for i in config['tasks']:
    if 'params' in i:
        if 'client_type' in i['params']:
            i['params']['client_type'] = client_type
with open(str(pathlib.Path.home())+'/.config/maa/tasks/daily.toml', 'w') as f:
    toml.dump(config, f)

# 运行 MAA
log = ""
start_time = time.time()  # 记录开始时间
start_time_str = time.strftime("%Y-%m-%d %H:%M:%S")  # 格式化开始时间
last_output_time = time.time()
timeout_triggered = False

def check_timeout():
    """检查是否超时的线程函数"""
    global timeout_triggered
    while True:
        time.sleep(60)  # 每分钟检查一次
        if time.time() - last_output_time > timeout_seconds:
            print(f"\n⚠️ 警告：MAA 已经 {timeout_seconds//3600} 小时没有新的日志输出，可能已卡住")
            print("🛑 正在终止 MAA 进程...")
            timeout_triggered = True
            try:
                process.terminate()
                time.sleep(5)
                if process.poll() is None:
                    process.kill()
            except:
                pass
            break

print(f"⏱️ 超时检测已启动，超时时间：{timeout_seconds//3600} 小时 ({timeout_seconds} 秒)")
print(f"🔍 日志模式：过滤 TRACE 级别日志（完整日志将保存到 asst.log 文件）\n")

# 启动 MAA 进程
process = subprocess.Popen("maa run daily", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# 启动超时检测线程
timeout_thread = threading.Thread(target=check_timeout, daemon=True)
timeout_thread.start()

# 读取 stderr（MAA 的日志输出）
flag_trace = False
if process.stderr:
    for line in process.stderr:
        log += line
        last_output_time = time.time()  # 更新最后输出时间
        
        # 过滤 TRACE 级别日志
        if '[' in line and ']' in line:
            if 'TRACE' in line[line.find('[')+1:line.find(']')]:
                flag_trace = True
            else:
                flag_trace = False
        if not flag_trace:
            print(line, end='', flush=True)

# 等待进程结束
process.wait()

# 读取 stdout（摘要信息）
if process.stdout:
    output = process.stdout.read()
    if output:
        print(output)
else:
    output = ""

# 检查是否因超时而终止
if timeout_triggered:
    print("\n" + "="*60)
    print("❌ MAA 因超时而被终止")
    print("⚠️ 本次运行的缓存将不会被保存，以避免保存异常状态")
    print("="*60)
    sys.exit(1)  # 以错误状态退出，GitHub Actions 会自动跳过后续步骤

# 提取摘要信息
summary = output[output.find('\n')+1:] if output and '\n' in output else ""

# 保存日志文件
with open('asst.log', 'w') as f:
    f.write(log)

# 保存摘要和时间信息
end_time_str = time.strftime("%Y-%m-%d %H:%M:%S")

# 计算总耗时
duration = int(time.time() - start_time)
hours = duration // 3600
minutes = (duration % 3600) // 60
seconds = duration % 60
if hours > 0:
    duration_str = f"{hours}h {minutes}m {seconds}s"
elif minutes > 0:
    duration_str = f"{minutes}m {seconds}s"
else:
    duration_str = f"{seconds}s"

# 保存摘要到文件
with open('msg', 'w') as f:
    f.write(summary)

# 保存时间信息到单独文件（三行：开始时间、结束时间、耗时）
with open('time_info', 'w') as f:
    f.write(f"{start_time_str}\n{end_time_str}\n{duration_str}")

print("\n✅ MAA execution completed.")
print("📝 Summary and time info saved to files.")
