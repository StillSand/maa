#!/bin/bash
# 清理旧的 GitHub Release
# 功能：保留最近 2 个 snapshot，删除其他旧版本

# ==================== 关于 set -e 的说明 ====================
# set -e：任何命令返回非零退出码时，脚本立即退出
#
# 为什么在某些地方必须禁用 set -e：
#
# 1. 删除操作可能失败，但我们需要：
#    - 捕获并显示详细的错误信息
#    - 继续处理其他删除操作
#    - 最后统一判断是否有失败
#    如果不禁用 set -e，第一次删除失败就会导致脚本退出，
#    无法看到错误信息，也无法处理后续操作。
#
# 2. 管道和循环操作（如 echo | grep | while）：
#    管道中任何命令失败都会触发 set -e 导致脚本退出。
#    即使是显示列表这种非关键操作也可能因此中断。
#
# 正确的错误处理模式：
#    set +e                    # 禁用自动退出
#    OUTPUT=$(command 2>&1)    # 执行命令并捕获输出
#    EXIT_CODE=$?              # 保存退出码
#    set -e                    # 重新启用自动退出
#    if [ $EXIT_CODE -ne 0 ]; then
#        # 处理错误
#    fi
# ==================== 说明结束 ====================

set -e  # 遇到错误立即退出

# ==================== 加载公共函数 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

# ==================== 配置 ====================
SNAPSHOT_PREFIX="snapshot"
KEEP_COUNT=2  # 保留最近几个 release（孤立 tag 会被全部删除）

# ==================== 检查依赖 ====================
check_dependencies() {
    log_info "检查依赖..."
    
    # 检查 gh (GitHub CLI)
    check_command gh "sudo apt update > /dev/null 2>&1 && sudo apt install -y gh > /dev/null 2>&1"
    
    log_success "依赖检查完成"
}

# ==================== 清理旧版本 ====================
cleanup_old_releases() {
    log_info "清理旧版本（保留最近 $KEEP_COUNT 个）..."
    
    # 使用公共函数获取所有 Release
    set +e
    RELEASES=$(list_snapshot_releases "$SNAPSHOT_PREFIX" true)
    local exit_code=$?
    set -e
    
    if [ $exit_code -ne 0 ]; then
        log_info "没有需要清理的 Release"
        return
    fi
    
    TOTAL_COUNT=$(echo "$RELEASES" | wc -l)
    
    # 安全检查：如果总数为0或异常，立即退出
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        log_error "错误：未找到任何 release，中止清理"
        return 1
    fi
    
    # 安全检查：如果总数小于等于保留数量，不需要清理
    if [ "$TOTAL_COUNT" -le "$KEEP_COUNT" ]; then
        log_info "当前只有 $TOTAL_COUNT 个 Release，无需清理"
        log_info "保留的 Release："
        echo "$RELEASES" | while read -r tag; do
            [ -n "$tag" ] && log_info "  - $tag"
        done
        return
    fi
    
    # 计算需要删除的数量
    DELETE_COUNT=$((TOTAL_COUNT - KEEP_COUNT))
    
    # 安全检查：确认删除数量合理
    if [ "$DELETE_COUNT" -ge "$TOTAL_COUNT" ]; then
        log_error "错误：删除数量($DELETE_COUNT) >= 总数($TOTAL_COUNT)，中止清理"
        return 1
    fi
    
    log_warning "将删除 $DELETE_COUNT 个旧版本（保留 $KEEP_COUNT 个）"
    
    # 显示保留的版本
    log_info "保留的 Release："
    KEEP_RELEASES=$(echo "$RELEASES" | head -n "$KEEP_COUNT")
    echo "$KEEP_RELEASES" | while read -r tag; do
        [ -n "$tag" ] && log_info "  - $tag"
    done
    
    echo ""
    
    # 显示将要删除的版本
    log_warning "将要删除的 Release："
    OLD_RELEASES=$(echo "$RELEASES" | tail -n +"$((KEEP_COUNT + 1))")
    echo "$OLD_RELEASES" | while read -r tag; do
        [ -n "$tag" ] && log_warning "  - $tag"
    done
    
    echo ""
    
    # 最终安全检查：确认要删除的 release 不在保留列表中
    log_info "执行安全检查..."
    while read -r tag; do
        [ -n "$tag" ] && {
            if echo "$KEEP_RELEASES" | grep -q "^${tag}$"; then
                log_error "错误：要删除的 release ($tag) 在保留列表中！中止清理"
                return 1
            fi
        }
    done <<< "$OLD_RELEASES"
    log_success "安全检查通过"
    echo ""
    
    # 删除旧版本
    log_info "开始删除..."
    DELETED_COUNT=0
    HAS_FAILURE=0
    
    # 禁用 set -e：删除操作可能失败，需要捕获错误信息并继续处理
    set +e
    
    # 使用 while read 从 here-string 读取，避免管道导致的子 shell 问题
    while IFS= read -r tag; do
        if [ -n "$tag" ]; then
            log_info "准备删除：$tag"
            
            # 捕获错误输出
            ERROR_OUTPUT=$(gh release delete "$tag" -y --cleanup-tag 2>&1)
            EXIT_CODE=$?
            
            if [ $EXIT_CODE -eq 0 ]; then
                log_success "已删除：$tag (包括 tag)"
                DELETED_COUNT=$((DELETED_COUNT + 1))
            else
                log_error "删除失败：$tag"
                log_error "错误信息：$ERROR_OUTPUT"
                log_error "退出码：$EXIT_CODE"
                HAS_FAILURE=1
            fi
        fi
    done <<< "$OLD_RELEASES"
    
    # 恢复 set -e
    set -e
    
    # 检查是否有失败
    if [ $HAS_FAILURE -eq 1 ]; then
        log_error "部分 release 删除失败，请查看上面的错误信息"
        return 1
    fi
    
    log_success "清理完成，已删除 $DELETED_COUNT 个旧版本（包括对应的 tag）"
}

# ==================== 清理残留的 tag ====================
cleanup_orphaned_tags() {
    log_info "检查残留的 tag..."
    
    # 获取所有 snapshot 开头的 tag
    set +e
    ALL_TAGS=$(git ls-remote --tags origin 2>&1 | grep "refs/tags/${SNAPSHOT_PREFIX}-" | awk -F'/' '{print $3}' | sed 's/\^{}//')
    set -e
    
    if [ -z "$ALL_TAGS" ]; then
        log_info "没有找到任何 ${SNAPSHOT_PREFIX} tag"
        return
    fi
    
    # 获取所有 release 的 tag
    set +e
    RELEASE_TAGS=$(list_snapshot_releases "$SNAPSHOT_PREFIX" false)
    set -e
    
    # 找出没有对应 release 的 tag（孤立 tag）
    ORPHANED_TAGS=""
    while read -r tag; do
        [ -n "$tag" ] && {
            if ! echo "$RELEASE_TAGS" | grep -q "^${tag}$"; then
                ORPHANED_TAGS="${ORPHANED_TAGS}${tag}\n"
            fi
        }
    done <<< "$ALL_TAGS"
    
    if [ -z "$ORPHANED_TAGS" ]; then
        log_info "没有残留的 tag"
        return
    fi
    
    # 计算有多少个孤立 tag
    ORPHANED_COUNT=$(echo -e "$ORPHANED_TAGS" | grep -v '^$' | wc -l)
    
    log_warning "发现 $ORPHANED_COUNT 个孤立 tag（没有对应的 release）"
    log_warning "孤立 tag 没有用处，将全部删除"
    
    # 显示要删除的孤立 tag
    log_warning "将要删除的孤立 tag："
    
    # 禁用 set -e：管道操作可能失败导致脚本退出
    set +e
    echo -e "$ORPHANED_TAGS" | grep -v '^$' | while read -r tag; do
        [ -n "$tag" ] && log_warning "  - $tag"
    done
    set -e
    
    echo ""
    
    # 删除孤立的 tag
    log_info "开始删除残留 tag..."
    DELETED_TAG_COUNT=0
    HAS_FAILURE=0
    
    # 禁用 set -e：删除操作可能失败，需要捕获错误信息并继续处理
    set +e
    
    # 使用 while read 从 here-string 读取，避免管道导致的子 shell 问题
    while IFS= read -r tag; do
        if [ -n "$tag" ]; then
            log_info "准备删除 tag：$tag"
            
            # 捕获错误输出
            ERROR_OUTPUT=$(git push origin --delete "refs/tags/${tag}" 2>&1)
            EXIT_CODE=$?
            
            if [ $EXIT_CODE -eq 0 ]; then
                log_success "已删除 tag：$tag"
                DELETED_TAG_COUNT=$((DELETED_TAG_COUNT + 1))
            else
                log_error "删除 tag 失败：$tag"
                log_error "错误信息：$ERROR_OUTPUT"
                log_error "退出码：$EXIT_CODE"
                HAS_FAILURE=1
            fi
        fi
    done <<< "$(echo -e "$ORPHANED_TAGS" | grep -v '^$')"
    
    # 恢复 set -e
    set -e
    
    # 检查是否有失败
    if [ $HAS_FAILURE -eq 1 ]; then
        log_error "部分 tag 删除失败，请查看上面的错误信息"
        return 1
    fi
    
    log_success "tag 清理完成，已删除 $DELETED_TAG_COUNT 个残留 tag"
}

# ==================== 显示统计信息 ====================
show_statistics() {
    log_info "当前 Release 统计..."
    
    # 使用公共函数获取所有 Release
    set +e
    RELEASES=$(list_snapshot_releases "$SNAPSHOT_PREFIX" false)
    local exit_code=$?
    set -e
    
    if [ $exit_code -ne 0 ]; then
        log_info "没有 snapshot Release"
        return
    fi
    
    TOTAL_COUNT=$(echo "$RELEASES" | wc -l)
    
    echo ""
    log_info "=========================================="
    log_info "  Release 统计"
    log_info "=========================================="
    log_info "总数：$TOTAL_COUNT 个"
    log_info "保留策略：最近 $KEEP_COUNT 个"
    echo ""
    log_info "当前 Release："
    echo "$RELEASES" | while read -r tag; do
        # 获取 Release 的创建时间
        CREATED=$(gh release view "$tag" --json createdAt -q .createdAt 2>/dev/null || echo "Unknown")
        log_info "  - $tag (创建于: $CREATED)"
    done
    log_info "=========================================="
    echo ""
}

# ==================== 主函数 ====================
main() {
    echo ""
    log_info "=========================================="
    log_info "  清理旧的 GitHub Release"
    log_info "=========================================="
    echo ""
    
    # 1. 检查依赖
    check_dependencies
    
    # 2. 清理旧版本（同时删除 release 和 tag）
    cleanup_old_releases
    
    # 3. 清理残留的 tag（之前删除 release 时没删除的 tag）
    cleanup_orphaned_tags
    
    # 4. 显示统计信息
    show_statistics
    
    echo ""
    log_success "=========================================="
    log_success "  清理完成！"
    log_success "=========================================="
    echo ""
}

# 执行主函数
main
