#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MAA 工具模块
提供日志读取、检测等通用功能
"""

import os
import re


def read_asst_log(filepath='asst.log'):
    """
    读取 MAA 日志文件
    
    Args:
        filepath: 日志文件路径，默认为 'asst.log'
    
    Returns:
        str: 日志内容，文件不存在返回空字符串
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return ""


def check_resource_update_error(log_content):
    """
    检查日志是否包含资源更新错误
    
    检测场景：
    - StartUp Error（开始唤醒失败，通常是游戏需要下载资源）
    - 多个任务连续失败（资源未准备好导致）
    
    Args:
        log_content: 日志内容
    
    Returns:
        bool: 是否需要资源更新修复
    """
    if not log_content:
        return False
    
    # 检测 StartUp Error（开始唤醒失败）
    # 这通常发生在游戏需要下载更新资源时
    startup_error_pattern = r'\[ERROR\].*StartUp Error'
    if re.search(startup_error_pattern, log_content):
        return True
    
    # 检测 GameStart 后的超时/错误
    # 日志中出现 GameStart 点击后长时间无响应
    gamestart_timeout_pattern = r'GameStart.*\n.*(?:StartUp Error|FailedToProcessMessage)'
    if re.search(gamestart_timeout_pattern, log_content, re.MULTILINE):
        return True
    
    # 检测多个核心任务连续失败（可能是资源未准备好）
    # 如果 StartUp、Recruit、Fight 都失败，很可能是资源问题
    core_tasks = ['StartUp', 'Recruit', 'Fight', 'Infrast', 'Mall']
    failed_tasks = []
    for task in core_tasks:
        if re.search(rf'\[ERROR\].*{task} Error', log_content):
            failed_tasks.append(task)
    
    # 如果超过3个核心任务失败，认为是资源问题
    if len(failed_tasks) >= 3:
        return True
    
    return False


def is_first_time_fix():
    """
    检查是否是第一次修复
    
    通过检查标志文件判断，避免死循环
    
    Returns:
        bool: 是否是第一次修复（True=是，False=已经修复过）
    """
    fix_flag_file = '.fix_game_update_done'
    return not os.path.exists(fix_flag_file)


def mark_fix_done():
    """
    标记修复已完成
    创建标志文件防止重复修复
    """
    fix_flag_file = '.fix_game_update_done'
    with open(fix_flag_file, 'w') as f:
        f.write('1')


def clear_fix_flag():
    """
    清除修复标志
    在 MAA 运行前调用，确保每次新运行都可以进行一次修复
    """
    fix_flag_file = '.fix_game_update_done'
    if os.path.exists(fix_flag_file):
        os.remove(fix_flag_file)
