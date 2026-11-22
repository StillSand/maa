#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
游戏资源更新修复脚本

当 MAA 因游戏需要下载资源而失败时：
1. 打开游戏
2. 等待1小时让游戏自动更新
3. 强制停止游戏
4. 重跑 MAA

注意：只执行一次修复，避免死循环
"""
import subprocess
import time
import sys
import os

from maa_utils import mark_fix_done, clear_fix_flag

# 游戏包名
GAME_PACKAGE = "com.hypergryph.arknights"
ADB_DEVICE = "127.0.0.1:5555"

# 等待时间（秒）- 1小时
WAIT_TIME = 3600


def run_adb_command(cmd):
    """运行 ADB 命令"""
    full_cmd = f"adb -s {ADB_DEVICE} {cmd}"
    try:
        result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timeout"


def connect_adb():
    """连接 ADB"""
    print("连接 ADB...")
    # 先 kill-server 再连接
    subprocess.run("adb kill-server", shell=True, capture_output=True)
    success, stdout, stderr = run_adb_command("connect 127.0.0.1:5555")
    if success:
        print("✓ ADB 连接成功")
        return True
    else:
        print(f"✗ ADB 连接失败: {stderr}")
        return False


def start_game():
    """启动游戏"""
    print(f"启动游戏 {GAME_PACKAGE}...")
    # 使用 monkey 命令启动应用（不需要知道 Activity 名）
    success, stdout, stderr = run_adb_command(
        f"shell monkey -p {GAME_PACKAGE} -c android.intent.category.LAUNCHER 1"
    )
    if success:
        print("✓ 游戏启动命令已发送")
        return True
    else:
        print(f"✗ 启动游戏失败: {stderr}")
        return False


def stop_game():
    """强制停止游戏"""
    print(f"强制停止游戏 {GAME_PACKAGE}...")
    success, stdout, stderr = run_adb_command(f"shell am force-stop {GAME_PACKAGE}")
    if success:
        print("✓ 游戏已停止")
        return True
    else:
        print(f"!停止游戏可能失败: {stderr}")
        # 即使失败也继续，可能游戏本来就不在运行
        return True


def wait_for_update():
    """等待游戏更新完成"""
    print(f"等待游戏自动更新...")
    print(f"   等待时间: {WAIT_TIME // 3600} 小时")
    print(f"   开始时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 每分钟显示一次进度
    for i in range(WAIT_TIME, 0, -60):
        minutes_left = i // 60
        if minutes_left % 10 == 0:  # 每10分钟显示一次
            print(f"   剩余时间: {minutes_left} 分钟")
        time.sleep(60)
    
    print(f"   结束时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("✓ 等待完成")


def run_maa():
    """重新运行 MAA"""
    print("↻ 重新运行 MAA...")
    
    # 调用 run.py 来运行 MAA
    # 但需要设置环境变量避免再次触发修复
    env = os.environ.copy()
    env['MAA_FIX_MODE'] = '1'  # 标记为修复模式运行
    
    result = subprocess.run([sys.executable, 'run.py'], env=env)
    return result.returncode


def main():
    """主函数 - 执行修复流程"""
    print("=" * 60)
    print(" 游戏资源更新修复模式")
    print("=" * 60)
    print()
    
    # 步骤1: 连接 ADB
    if not connect_adb():
        print("✗ ADB 连接失败，无法继续修复")
        sys.exit(1)
    
    # 步骤2: 启动游戏
    if not start_game():
        print("✗ 启动游戏失败")
        sys.exit(1)
    
    print()
    print("游戏应该正在运行并自动下载资源...")
    print()
    
    # 步骤3: 等待1小时
    wait_for_update()
    
    print()
    
    # 步骤4: 停止游戏
    stop_game()
    
    print()
    
    # 标记修复已完成（防止死循环）
    mark_fix_done()
    
    # 步骤5: 重新运行 MAA
    print("↻ 现在重新运行 MAA...")
    print("=" * 60)
    print()
    
    exit_code = run_maa()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
