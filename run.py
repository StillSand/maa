#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
运行 MAA 日常，并处理“卡在进入游戏”的情况。

判断依据是 MAA 自己的日志：
- 每条 `TASK Start` / `TASK Completed` 都会记录当前任务和开始时间
- 单个任务（通常是 StartUp）超过 MAA_TASK_TIMEOUT（默认 3 小时）仍没完成，
  且设备在线、MAA 已连上，则停止游戏并重新拉起 MAA
- 等待期间如果检测到游戏正在下载资源，等下载结束（连续 3 分钟无增长）后提前重启
- 没有任何任务在跑、且 MAA_TASK_TIMEOUT 时间没有新日志，按卡死处理
"""
import os
import pathlib
import re
import subprocess
import sys
import threading
import time

import toml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from maa_utils import clear_fix_flag

GAME_PACKAGE = "com.hypergryph.arknights"
ADB_DEVICE = "127.0.0.1:5555"

# 没有任何任务时，多久没有日志判定为卡死（秒）
INACTIVITY_TIMEOUT = int(os.getenv("MAA_TIMEOUT", "7200"))
# 单个任务最长运行时间（秒），默认 3 小时
TASK_TIMEOUT = int(os.getenv("MAA_TASK_TIMEOUT", "10800"))
# 更新完成后重启 MAA 的最大次数
MAX_RESTARTS = int(os.getenv("MAA_MAX_RESTARTS", "1"))

# 下载判定
SAMPLE_AFTER = 600                  # 任务运行 10 分钟后开始采样
GROWTH_KB_PER_MIN = 2048            # 数据目录 1 分钟增长 2MB
GROWTH_BYTES_PER_MIN = 2 * 1024 * 1024  # 或网卡 1 分钟接收 2MB
QUIET_SECONDS = 180                 # 连续 3 分钟无增长，视为下载结束

TASK_START_RE = re.compile(r"INFO \] ([A-Za-z]+) Start\s*$")
TASK_DONE_RE = re.compile(r"INFO \] ([A-Za-z]+) Completed\s*$")

if os.getenv("MAA_FIX_MODE") != "1":
    clear_fix_flag()

client_type = os.getenv("CLIENT_TYPE", "Official")
config_path = pathlib.Path.home() / ".config/maa/tasks/daily.toml"
config = toml.load(str(config_path))
for task in config["tasks"]:
    if "params" in task and "client_type" in task["params"]:
        task["params"]["client_type"] = client_type
with open(config_path, "w") as f:
    toml.dump(config, f)


def adb_shell(command, timeout=20):
    try:
        result = subprocess.run(
            ["adb", "-s", ADB_DEVICE, "shell", command],
            capture_output=True, text=True, timeout=timeout,
        )
        return result.returncode == 0, result.stdout.strip()
    except Exception:
        return False, ""


def device_online():
    ok, out = adb_shell("getprop sys.boot_completed")
    return ok and out.strip() == "1"


def game_data_kb():
    for path in (
        "/data/data/%s" % GAME_PACKAGE,
        "/sdcard/Android/data/%s" % GAME_PACKAGE,
    ):
        ok, out = adb_shell("du -sk %s 2>/dev/null" % path)
        if ok and out:
            first = out.split()[0]
            if first.isdigit():
                return int(first)
    return None


def net_rx_bytes():
    """累计接收字节，排除回环和容器网桥，避免 adb 截图流量误判"""
    ok, out = adb_shell("cat /proc/net/dev")
    if not ok or not out:
        return None
    total = 0
    for line in out.splitlines():
        if ":" not in line or "|" in line:
            continue
        iface = line.split(":")[0].strip()
        if iface == "lo" or iface.startswith(("docker", "veth", "tun", "tap")):
            continue
        try:
            total += int(line.split(":")[1].split()[0])
        except (IndexError, ValueError):
            continue
    return total


def game_in_foreground():
    for command in (
        "dumpsys activity activities | grep -m1 mResumedActivity",
        "dumpsys window | grep -m1 mCurrentFocus",
    ):
        ok, out = adb_shell(command)
        if ok and out:
            return GAME_PACKAGE in out
    return False


def sample_device():
    return (time.time(), game_data_kb(), net_rx_bytes(), game_in_foreground())


def grew(prev, cur):
    if not prev or not cur:
        return False
    if prev[1] is not None and cur[1] is not None:
        if cur[1] - prev[1] >= GROWTH_KB_PER_MIN:
            return True
    if prev[2] is not None and cur[2] is not None:
        if cur[2] - prev[2] >= GROWTH_BYTES_PER_MIN:
            return True
    return False


def terminate(process):
    try:
        process.terminate()
        time.sleep(5)
        if process.poll() is None:
            process.kill()
    except Exception:
        pass


def stop_game():
    adb_shell("am force-stop %s" % GAME_PACKAGE)
    time.sleep(2)


def trigger_restart(state, process, reason):
    print("! %s" % reason, flush=True)
    print("  停止游戏，重新拉起 MAA", flush=True)
    stop_game()
    state["restart"] = True
    state["task"] = None
    state["task_start"] = None
    state["last_output"] = time.time()
    terminate(process)


def watchdog(state):
    last_sample = None
    last_growth = None
    last_report = 0.0
    observed_task = None

    while not state["done"]:
        time.sleep(30)
        process = state.get("process")
        if process is None or process.poll() is not None:
            continue

        now = time.time()
        task = state.get("task")
        task_start = state.get("task_start")

        # 没有任务在跑：按无日志超时处理
        if not task:
            if now - state["last_output"] >= INACTIVITY_TIMEOUT:
                print("! MAA 已 %d 分钟没有新的日志输出，判定为卡住" %
                      ((now - state["last_output"]) // 60), flush=True)
                print("  正在终止 MAA 进程...", flush=True)
                state["timeout"] = True
                terminate(process)
                return
            continue

        if task != observed_task:
            observed_task = task
            last_sample = None
            last_growth = None

        elapsed = now - task_start
        if elapsed < SAMPLE_AFTER:
            continue

        current = sample_device()
        growing = grew(last_sample, current)
        last_sample = current
        if growing:
            last_growth = now

        progress = ""
        if current[1] is not None:
            progress = "，数据目录 %d MB" % (current[1] // 1024)

        if now - last_report >= 600:
            print("   任务 %s 已运行 %d 分钟%s%s" %
                  (task, elapsed // 60, progress,
                   "（下载中）" if growing else ""), flush=True)
            last_report = now

        # 下载结束：提前重启
        if last_growth and now - last_growth >= QUIET_SECONDS:
            trigger_restart(state, process,
                            "游戏资源下载已结束（连续 %d 分钟无增长）" % (QUIET_SECONDS // 60))
            last_sample = None
            last_growth = None
            continue

        # 任务超时：设备在线则重启，否则放弃
        if elapsed >= TASK_TIMEOUT:
            if device_online():
                trigger_restart(state, process,
                                "任务 %s 已运行 %d 分钟仍未完成" %
                                (task, elapsed // 60))
            else:
                print("✗ 任务 %s 已运行 %d 分钟，且设备离线" %
                      (task, elapsed // 60), flush=True)
                state["timeout"] = True
                terminate(process)
                return
            last_sample = None
            last_growth = None
            continue


print("任务监控已启动：单个任务最长 %d 分钟" % (TASK_TIMEOUT // 60))
print("无任务时：%d 分钟无日志判定为卡死" % (INACTIVITY_TIMEOUT // 60))
print("超过时限后：设备在线则重启 MAA（最多 %d 次）" % MAX_RESTARTS)
print("日志模式：过滤 TRACE 级别日志（完整日志将保存到 asst.log 文件）\n")

start_time = time.time()
start_time_str = time.strftime("%Y-%m-%d %H:%M:%S")
state = {
    "process": None,
    "last_output": time.time(),
    "task": None,
    "task_start": None,
    "timeout": False,
    "restart": False,
    "done": False,
}

threading.Thread(target=watchdog, args=(state,), daemon=True).start()

log = ""
output = ""
attempt = 0

while True:
    attempt += 1
    if attempt > 1:
        print("\n↻ 重新启动 MAA（第 %d 次）...\n" % (attempt - 1), flush=True)

    state["process"] = subprocess.Popen(
        "maa run daily", shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    state["last_output"] = time.time()
    state["task"] = None
    state["task_start"] = None

    flag_trace = False
    for line in state["process"].stderr:
        log += line
        state["last_output"] = time.time()

        start_match = TASK_START_RE.search(line)
        if start_match:
            state["task"] = start_match.group(1)
            state["task_start"] = time.time()
        elif TASK_DONE_RE.search(line):
            state["task"] = None
            state["task_start"] = None

        if "[" in line and "]" in line:
            level = line[line.find("[") + 1:line.find("]")]
            flag_trace = "TRACE" in level
        if not flag_trace:
            print(line, end="", flush=True)

    state["process"].wait()
    if state["process"].stdout:
        output = state["process"].stdout.read()

    if state["timeout"]:
        break
    if state["restart"]:
        if attempt <= MAX_RESTARTS:
            state["restart"] = False
            time.sleep(5)
            continue
        state["timeout"] = True
        break
    break

state["done"] = True

end_time_str = time.strftime("%Y-%m-%d %H:%M:%S")
duration = int(time.time() - start_time)
hours = duration // 3600
minutes = (duration % 3600) // 60
seconds = duration % 60
if hours > 0:
    duration_str = "%dh %dm %ds" % (hours, minutes, seconds)
elif minutes > 0:
    duration_str = "%dm %ds" % (minutes, seconds)
else:
    duration_str = "%ds" % seconds

with open("asst.log", "w") as f:
    f.write(log)

with open("time_info", "w") as f:
    f.write("%s\n%s\n%s" % (start_time_str, end_time_str, duration_str))

if state["timeout"]:
    print("\n" + "=" * 60)
    print("✗ MAA 因超时而被终止")
    print("! 本次运行的缓存将不会被保存，以避免保存异常状态")
    print("=" * 60)
    sys.exit(1)

summary = output[output.find("\n") + 1:] if output and "\n" in output else ""
with open("msg", "w") as f:
    f.write(summary)

print("\n✓ MAA execution completed.")
print("Summary and time info saved to files.")