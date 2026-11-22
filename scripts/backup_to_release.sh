#!/bin/bash
# 备份容器到 GitHub Release
# 功能：压缩 + 加密 + 分卷 + 上传

set -e  # 遇到错误立即退出

# ==================== 加载公共函数 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

# ==================== 配置 ====================
ENCRYPTION_KEY="${CONTAINER_ENCRYPTION_KEY}"
SPLIT_SIZE="1900m"  # 每个分卷大小（GitHub Release 限制 2GB）
SNAPSHOT_PREFIX="snapshot"

# 压缩级别配置（gzip 级别）
# 0 = 不压缩（最快，2-3分钟，~12GB）
# 1 = 最快压缩（推荐，3-5分钟，~10GB）
# 6 = 标准压缩（5-8分钟，~9GB）
# 9 = 最大压缩（8-12分钟，~8GB）
COMPRESSION_LEVEL="1"

# ==================== 检查依赖 ====================
check_dependencies() {
    log_info "检查依赖..."
    
    # 检查必需工具（Ubuntu 自带）
    for cmd in tar gzip openssl split; do
        if ! command -v $cmd &> /dev/null; then
            log_error "未找到 $cmd 命令"
            exit 1
        fi
    done
    
    # 检查 gh (GitHub CLI)
    check_command gh "sudo apt update > /dev/null 2>&1 && sudo apt install -y gh > /dev/null 2>&1"
    
    log_success "依赖检查完成"
}

# ==================== 检查加密密码 ====================
check_encryption_key() {
    log_info "检查加密密码..."
    
    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "未配置加密密码！"
        log_error "请在 GitHub Secrets 中添加 CONTAINER_ENCRYPTION_KEY"
        log_error "路径：Settings → Secrets and variables → Actions → New repository secret"
        exit 1
    fi
    
    log_success "加密密码已配置"
}

# ==================== 检查必需文件 ====================
check_required_files() {
    log_info "检查必需文件..."
    
    if [ ! -f "ark.tar" ]; then
        log_error "未找到 ark.tar 文件"
        exit 1
    fi
    
    if [ ! -f "data.tar" ]; then
        log_error "未找到 data.tar 文件"
        exit 1
    fi
    
    # 显示文件大小
    ARK_SIZE=$(du -h ark.tar | cut -f1)
    DATA_SIZE=$(du -h data.tar | cut -f1)
    log_info "ark.tar: $ARK_SIZE"
    log_info "data.tar: $DATA_SIZE"
    
    log_success "文件检查完成"
}

# ==================== 压缩 + 加密 + 分卷 ====================
compress_and_encrypt() {
    log_info "开始压缩、加密和分卷..."
    
    # 清理旧的分卷文件
    rm -f container.enc.* 2>/dev/null || true
    
    # 显示原始大小
    ORIGINAL_SIZE=$(du -ch ark.tar data.tar | tail -1 | cut -f1)
    log_info "原始大小: $ORIGINAL_SIZE"
    log_info "压缩级别: $COMPRESSION_LEVEL, 分卷大小: $SPLIT_SIZE"
    
    # tar → gzip → openssl → split（流式处理）
    log_info "正在处理（这可能需要 3-6 分钟）..."
    
    # 根据压缩级别选择处理方式
    if [ "$COMPRESSION_LEVEL" = "0" ]; then
        # 压缩级别 0：不压缩，直接 tar → openssl → split
        log_info "使用无压缩模式（最快）"
        if tar -cf - ark.tar data.tar | \
           openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass pass:"$ENCRYPTION_KEY" | \
           split -b "$SPLIT_SIZE" -d -a 3 - container.enc.; then
            log_success "加密和分卷完成"
        else
            log_error "处理失败"
            exit 1
        fi
    else
        # 压缩级别 1-9：tar → gzip → openssl → split
        log_info "使用 gzip 压缩（级别 $COMPRESSION_LEVEL）"
        if tar -cf - ark.tar data.tar | \
           gzip -$COMPRESSION_LEVEL | \
           openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass pass:"$ENCRYPTION_KEY" | \
           split -b "$SPLIT_SIZE" -d -a 3 - container.enc.; then
            log_success "压缩、加密和分卷完成"
        else
            log_error "处理失败"
            exit 1
        fi
    fi
    
    # 检查是否生成了分卷文件
    if [ ! -f "container.enc.000" ]; then
        log_error "分卷失败，未生成文件"
        exit 1
    fi
    
    # 统计分卷数量和总大小
    PART_COUNT=$(ls container.enc.* 2>/dev/null | wc -l)
    FINAL_SIZE=$(du -ch container.enc.* 2>/dev/null | tail -1 | cut -f1)
    
    log_success "完成：生成 $PART_COUNT 个分卷，总大小 $FINAL_SIZE"
    
    # 显示压缩率
    ORIGINAL_BYTES=$(du -cb ark.tar data.tar | tail -1 | cut -f1)
    FINAL_BYTES=$(du -cb container.enc.* | tail -1 | cut -f1)
    if [ "$ORIGINAL_BYTES" -gt 0 ]; then
        COMPRESSION_RATIO=$(awk "BEGIN {printf \"%.1f\", (1 - $FINAL_BYTES / $ORIGINAL_BYTES) * 100}")
        log_info "压缩率: ${COMPRESSION_RATIO}%"
    fi
    
    # 列出所有分卷
    log_info "分卷列表："
    ls -lh container.enc.* | awk '{print "  - " $9 " (" $5 ")"}'
}

# ==================== 生成 Release 标签 ====================
generate_release_tag() {
    # 格式：snapshot-YYYYMMDD-HHMM
    RELEASE_TAG="${SNAPSHOT_PREFIX}-$(date -u +%Y%m%d-%H%M)"
    echo "$RELEASE_TAG"
}

# ==================== 上传到 GitHub Release ====================
upload_to_release() {
    log_info "准备上传到 GitHub Release..."
    
    RELEASE_TAG=$(generate_release_tag)
    log_info "Release 标签：$RELEASE_TAG"
    
    # 检查 Release 是否已存在
    if gh release view "$RELEASE_TAG" &>/dev/null; then
        log_warning "Release $RELEASE_TAG 已存在，将删除后重新创建"
        gh release delete "$RELEASE_TAG" -y
    fi
    
    # 创建 Release 并上传文件
    log_info "创建 Release 并上传文件..."
    gh release create "$RELEASE_TAG" \
        container.enc.* \
        --title "Container Snapshot $(date -u +%Y-%m-%d\ %H:%M) UTC" \
        --notes "Automated container backup

Files: $(ls container.enc.* | wc -l) parts
Total size: $(du -ch container.enc.* | tail -1 | cut -f1)
Encryption: OpenSSL AES-256-CBC
Created: $(date -u +%Y-%m-%d\ %H:%M:%S) UTC"
    
    log_success "上传完成：$RELEASE_TAG"
}

# ==================== 清理临时文件 ====================
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    rm -f container.enc.* 2>/dev/null || true
    
    log_success "清理完成"
}

# ==================== 清理旧版本 ====================
cleanup_old_releases() {
    log_info "清理旧版本（保留最近 2 个）..."
    
    # 使用公共函数获取所有 Release
    set +e
    RELEASES=$(list_snapshot_releases "$SNAPSHOT_PREFIX" false)
    local exit_code=$?
    set -e
    
    if [ $exit_code -ne 0 ]; then
        log_info "没有需要清理的 Release"
        return
    fi
    
    TOTAL_COUNT=$(echo "$RELEASES" | wc -l)
    KEEP_COUNT=2
    
    log_info "找到 $TOTAL_COUNT 个 snapshot Release"
    
    # 如果总数小于等于保留数量，不需要清理
    if [ "$TOTAL_COUNT" -le "$KEEP_COUNT" ]; then
        log_info "当前只有 $TOTAL_COUNT 个 Release，无需清理"
        return
    fi
    
    # 计算需要删除的数量
    DELETE_COUNT=$((TOTAL_COUNT - KEEP_COUNT))
    log_warning "将删除 $DELETE_COUNT 个旧版本"
    
    # 获取需要删除的旧版本（跳过最新的 KEEP_COUNT 个）
    OLD_RELEASES=$(echo "$RELEASES" | tail -n +"$((KEEP_COUNT + 1))")
    
    # 删除旧版本
    DELETED_COUNT=0
    HAS_FAILURE=0
    
    # 禁用 set -e：删除操作可能失败，需要捕获错误信息并继续处理
    set +e
    
    echo "$OLD_RELEASES" | while read -r tag; do
        [ -n "$tag" ] && {
            log_info "删除旧版本：$tag"
            
            # 捕获错误输出
            ERROR_OUTPUT=$(gh release delete "$tag" -y --cleanup-tag 2>&1)
            EXIT_CODE=$?
            
            if [ $EXIT_CODE -eq 0 ]; then
                log_success "已删除：$tag (包括 tag)"
                DELETED_COUNT=$((DELETED_COUNT + 1))
            else
                log_error "删除失败：$tag"
                log_error "错误信息：$ERROR_OUTPUT"
                HAS_FAILURE=1
            fi
        }
    done
    
    # 恢复 set -e
    set -e
    
    if [ $HAS_FAILURE -eq 1 ]; then
        log_warning "部分 release 删除失败，将尝试清理残留的 tag"
    else
        log_success "旧版本清理完成"
    fi
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
    log_warning "孤立 tag 列表："
    
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

# ==================== 主函数 ====================
main() {
    echo ""
    log_info "=========================================="
    log_info "  备份容器到 GitHub Release"
    log_info "=========================================="
    echo ""
    
    # 1. 检查依赖
    check_dependencies
    
    # 2. 检查加密密码
    check_encryption_key
    
    # 3. 检查必需文件
    check_required_files
    
    # 4. 压缩 + 加密 + 分卷
    compress_and_encrypt
    
    # 5. 上传到 Release
    upload_to_release
    
    # 6. 清理临时文件
    cleanup_temp_files
    
    # 7. 清理旧版本
    cleanup_old_releases
    
    # 8. 清理残留的 tag
    cleanup_orphaned_tags
    
    echo ""
    log_success "=========================================="
    log_success "  备份完成！"
    log_success "=========================================="
    echo ""
}

# 执行主函数
main
