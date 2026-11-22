#!/bin/bash
# 公共函数库
# 提供可复用的工具函数

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}i $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

# ==================== 列出所有 snapshot Release ====================
# 用法：list_snapshot_releases [SNAPSHOT_PREFIX] [DEBUG]
# 参数：
#   SNAPSHOT_PREFIX: snapshot 前缀，默认 "snapshot"
#   DEBUG: 是否显示调试信息，默认 false
# 返回：
#   成功：输出所有 snapshot release tags（每行一个）
#   失败：返回 1
list_snapshot_releases() {
    local prefix="${1:-snapshot}"
    local debug="${2:-false}"
    
    if [ "$debug" = "true" ]; then
        log_info "获取所有 ${prefix} Release..." >&2
        log_info "调试：列出所有 releases..." >&2
        echo "--- gh release list 输出 (前10个) ---" >&2
        gh release list --limit 10 2>&1 | head -10 >&2 || {
            log_error "gh release list 命令失败" >&2
            return 1
        }
        echo "--- 输出结束 ---" >&2
        echo "" >&2
    fi
    
    # 关键：使用 tab 作为分隔符，tag 在第 3 列
    set +e
    local releases=$(gh release list --limit 100 2>&1 | awk -F'\t' '{print $3}' | grep "^${prefix}-")
    local grep_exit=$?
    set -e
    
    if [ $grep_exit -ne 0 ] || [ -z "$releases" ]; then
        if [ "$debug" = "true" ]; then
            log_info "未找到任何 ${prefix} Release" >&2
            log_info "所有 release tags:" >&2
            gh release list --limit 100 2>&1 | awk -F'\t' '{print "  - " $3}' >&2 || echo "  (无法列出)" >&2
        fi
        return 1
    fi
    
    if [ "$debug" = "true" ]; then
        local count=$(echo "$releases" | wc -l)
        log_info "找到 $count 个 ${prefix} Release" >&2
        echo "$releases" | while read -r tag; do
            log_info "  - $tag" >&2
        done
        echo "" >&2
    fi
    
    # 只返回实际的结果到 stdout
    echo "$releases"
}

# ==================== 获取最新的 snapshot Release ====================
# 用法：get_latest_snapshot_release [SNAPSHOT_PREFIX] [DEBUG]
# 参数：
#   SNAPSHOT_PREFIX: snapshot 前缀，默认 "snapshot"
#   DEBUG: 是否显示调试信息，默认 false
# 返回：
#   成功：输出最新的 snapshot release tag
#   失败：返回 1
get_latest_snapshot_release() {
    local prefix="${1:-snapshot}"
    local debug="${2:-false}"
    
    set +e
    local releases=$(list_snapshot_releases "$prefix" "$debug")
    local exit_code=$?
    set -e
    
    if [ $exit_code -ne 0 ] || [ -z "$releases" ]; then
        return 1
    fi
    
    # 返回第一个（最新的）
    echo "$releases" | head -1
}

# ==================== 检查依赖 ====================
# 用法：check_command <command_name> [install_command]
# 参数：
#   command_name: 要检查的命令名
#   install_command: 可选的安装命令
check_command() {
    local cmd=$1
    local install_cmd=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        if [ -n "$install_cmd" ]; then
            log_error "未找到 $cmd 命令，正在安装..."
            eval "$install_cmd"
            log_success "$cmd 安装完成"
        else
            log_error "未找到 $cmd 命令"
            return 1
        fi
    fi
}
