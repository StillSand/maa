#!/bin/bash
# 从 GitHub Release 恢复容器
# 功能：下载 + 合并 + 解密

set -e  # 遇到错误立即退出

# ==================== 配置 ====================
ENCRYPTION_KEY="${CONTAINER_ENCRYPTION_KEY}"
SNAPSHOT_PREFIX="snapshot"

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

# ==================== 检查依赖 ====================
check_dependencies() {
    log_info "检查依赖..."
    
    # 检查必需工具（Ubuntu 自带）
    for cmd in tar gzip openssl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "未找到 $cmd 命令"
            exit 1
        fi
    done
    
    # 检查 gh (GitHub CLI)
    if ! command -v gh &> /dev/null; then
        log_error "未找到 gh 命令，正在安装..."
        sudo apt update > /dev/null 2>&1
        sudo apt install -y gh > /dev/null 2>&1
        log_success "gh 安装完成"
    fi
    
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

# ==================== 查找最新的 Release ====================
find_latest_release() {
    # 所有调试信息输出到 stderr，避免被 $() 捕获
    echo "i 查找最新的容器备份..." >&2
    echo "" >&2
    
    # 调试：检查 gh 命令是否可用
    echo "i 调试 [1/4]: 检查 gh 命令..." >&2
    if command -v gh &> /dev/null; then
        echo "✓ gh 命令存在: $(which gh)" >&2
        gh --version >&2 2>&1 || echo "! 无法获取 gh 版本" >&2
    else
        echo "✗ gh 命令不存在" >&2
        exit 1
    fi
    echo "" >&2
    
    # 调试：检查 GH_TOKEN
    echo "i 调试 [2/4]: 检查 GH_TOKEN..." >&2
    if [ -z "$GH_TOKEN" ]; then
        echo "✗ GH_TOKEN 未设置" >&2
        exit 1
    else
        echo "✓ GH_TOKEN 已设置 (长度: ${#GH_TOKEN})" >&2
    fi
    echo "" >&2
    
    # 调试：显示 gh release list 的输出
    echo "i 调试 [3/4]: 列出所有 releases..." >&2
    echo "--- gh release list 输出 (前10个) ---" >&2
    gh release list --limit 10 >&2 2>&1 || {
        echo "✗ gh release list 命令失败，错误码: $?" >&2
        exit 1
    }
    echo "--- 输出结束 ---" >&2
    echo "" >&2
    
    # 调试：提取和过滤过程
    echo "i 调试 [4/4]: 查找 snapshot releases..." >&2
    echo "  SNAPSHOT_PREFIX = '${SNAPSHOT_PREFIX}'" >&2
    echo "  查找模式 = '^${SNAPSHOT_PREFIX}-'" >&2
    echo "" >&2
    
    # 关键修复：使用 tab 作为分隔符，tag 在第 3 列
    # 注意：不使用 2>&1，避免 stderr 混入结果
    set +e
    LATEST_RELEASE=$(gh release list --limit 100 2>/dev/null | awk -F'\t' '{print $3}' | grep "^${SNAPSHOT_PREFIX}-" | head -1)
    GREP_EXIT_CODE=$?
    set -e
    
    # 调试：显示提取结果（清理前）
    echo "--- 提取结果（清理前）---" >&2
    echo "原始值: [$LATEST_RELEASE]" >&2
    echo "长度: ${#LATEST_RELEASE}" >&2
    echo "十六进制: $(echo -n "$LATEST_RELEASE" | xxd -p | head -c 100)" >&2
    echo "" >&2
    
    # 清理可能的空白字符和换行符
    LATEST_RELEASE=$(echo "$LATEST_RELEASE" | tr -d '\n\r\t ' | xargs)
    
    # 调试：显示提取结果（清理后）
    echo "--- 提取结果（清理后）---" >&2
    if [ $GREP_EXIT_CODE -eq 0 ] && [ -n "$LATEST_RELEASE" ]; then
        echo "✓ 找到匹配: [$LATEST_RELEASE]" >&2
        echo "长度: ${#LATEST_RELEASE}" >&2
    else
        echo "✗ 未找到匹配 (grep exit code: $GREP_EXIT_CODE)" >&2
        echo "所有 release tags:" >&2
        gh release list --limit 100 2>/dev/null | awk -F'\t' '{print "  - " $3}' >&2 || echo "  (无法列出)" >&2
    fi
    echo "--- 提取结果结束 ---" >&2
    echo "" >&2
    
    if [ -z "$LATEST_RELEASE" ]; then
        echo "✗ 未找到任何容器备份" >&2
        echo "请先运行 Setup workflow 创建初始备份" >&2
        exit 1
    fi
    
    echo "✓ 找到最新备份：$LATEST_RELEASE" >&2
    # 只有这一行输出到 stdout，会被 $() 捕获
    echo "$LATEST_RELEASE"
}

# ================ 下载 Release 文件 ====================
download_release_files() {
    local release_tag=$1
    
    log_info "下载备份文件..."
    
    # 清理旧的下载文件
    rm -f container.enc.* 2>/dev/null || true
    
    # 获取文件列表和总数
    log_info "获取文件列表..."
    
    # 检查备份文件
    if ! gh release view "$release_tag" --json assets --jq '.assets[].name' | grep -q "container.enc."; then
        log_error "未找到备份文件（container.enc.*）"
        exit 1
    fi
    
    FILE_PATTERN="container.enc."
    
    FILE_LIST=$(gh release view "$release_tag" --json assets --jq '.assets[].name' | grep "$FILE_PATTERN")
    TOTAL_FILES=$(echo "$FILE_LIST" | wc -l)
    
    log_info "需要下载 $TOTAL_FILES 个分卷文件"
    log_info "并行下载中..."
    echo ""
    
    # 并行下载所有文件
    for file in $FILE_LIST; do
        (
            gh release download "$release_tag" --pattern "$file" --clobber > /dev/null 2>&1
            if [ -f "$file" ]; then
                FILE_SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
                echo "✓ $file ($FILE_SIZE)"
            else
                echo "✗ $file 下载失败"
            fi
        ) &
    done
    
    # 等待所有下载完成，显示进度
    echo "等待下载完成..."
    echo ""
    WAIT_COUNT=0
    while true; do
        DOWNLOADED=$(ls ${FILE_PATTERN}* 2>/dev/null | wc -l)
        # 只统计已完全下载的文件大小（避免显示不准确的中间值）
        if [ "$DOWNLOADED" -gt 0 ]; then
            TOTAL_SIZE=$(du -ch ${FILE_PATTERN}* 2>/dev/null | tail -1 | cut -f1 || echo "0")
        else
            TOTAL_SIZE="0"
        fi
        
        # 使用 \r 覆盖当前行，显示实时进度
        printf "\r   进度: %d/%d 文件，已下载: %s    " "$DOWNLOADED" "$TOTAL_FILES" "$TOTAL_SIZE"
        
        if [ "$DOWNLOADED" -eq "$TOTAL_FILES" ]; then
            break
        fi
        
        WAIT_COUNT=$((WAIT_COUNT + 1))
        if [ $WAIT_COUNT -gt 600 ]; then
            echo ""
            log_error "下载超时（10分钟）"
            exit 1
        fi
        
        sleep 2
    done
    
    # 等待所有后台进程完成
    wait
    
    # 清除进度行，打印最终结果
    printf "\r%80s\r" " "  # 清除整行
    echo ""
    
    # 检查是否下载成功
    if [ ! -f "container.enc.000" ]; then
        log_error "下载失败，未找到 container.enc.000"
        exit 1
    fi
    
    # 统计下载的文件
    PART_COUNT=$(ls ${FILE_PATTERN}* 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -ch ${FILE_PATTERN}* 2>/dev/null | tail -1 | cut -f1)
    
    log_success "下载完成：$PART_COUNT 个分卷，总大小 $TOTAL_SIZE"
    
    # 列出所有分卷
    log_info "下载的文件："
    ls -lh ${FILE_PATTERN}* | awk '{print "  - " $9 " (" $5 ")"}'
}

# ==================== 解压 + 解密 ====================
extract_and_decrypt() {
    log_info "开始解密和解压..."
    
    # 清理旧的解压文件
    rm -f ark.tar data.tar 2>/dev/null || true
    
    log_info "使用 OpenSSL 解密（这可能需要 2-5 分钟）..."
    
    # 尝试方法 1：cat → openssl → gunzip → tar（假设有 gzip 压缩）
    log_info "尝试解密（带 gzip 解压）..."
    if cat container.enc.* | \
       openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:"$ENCRYPTION_KEY" | \
       gunzip | \
       tar -xf -; then
        log_success "解密和解压完成"
    else
        # 方法 1 失败，尝试方法 2：cat → openssl → tar（无 gzip 压缩）
        log_warning "带 gzip 解压失败，尝试无压缩模式..."
        
        # 清理可能的部分解压文件
        rm -f ark.tar data.tar 2>/dev/null || true
        
        if cat container.enc.* | \
           openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass pass:"$ENCRYPTION_KEY" | \
           tar -xf -; then
            log_success "解密和解压完成（无压缩模式）"
        else
            log_error "解密失败！"
            log_error "可能的原因："
            log_error "  1. 密码错误"
            log_error "  2. 文件损坏"
            log_error "  3. 分卷文件不完整"
            exit 1
        fi
    fi
    
    # 检查是否成功解压
    if [ ! -f "ark.tar" ] || [ ! -f "data.tar" ]; then
        log_error "解压失败，未找到 ark.tar 或 data.tar"
        exit 1
    fi
    
    # 显示解压后的文件大小
    ARK_SIZE=$(du -h ark.tar | cut -f1)
    DATA_SIZE=$(du -h data.tar | cut -f1)
    log_info "ark.tar: $ARK_SIZE"
    log_info "data.tar: $DATA_SIZE"
}

# ==================== 清理临时文件 ====================
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    rm -f container.enc.* 2>/dev/null || true
    
    log_success "清理完成"
}

# ==================== 验证文件完整性 ====================
verify_files() {
    log_info "验证文件..."
    
    # 检查文件是否存在
    if [ ! -f "ark.tar" ]; then
        log_error "ark.tar 不存在"
        exit 1
    fi
    
    if [ ! -f "data.tar" ]; then
        log_error "data.tar 不存在"
        exit 1
    fi
    
    # 显示文件大小
    ARK_SIZE=$(du -h ark.tar | cut -f1)
    DATA_SIZE=$(du -h data.tar | cut -f1)
    log_info "ark.tar: $ARK_SIZE"
    log_info "data.tar: $DATA_SIZE"
    
    log_success "文件验证完成"
}

# ==================== 主函数 ====================
main() {
    echo ""
    log_info "=========================================="
    log_info "  从 GitHub Release 恢复容器"
    log_info "=========================================="
    echo ""
    
    # 1. 检查依赖
    check_dependencies
    
    # 2. 检查加密密码
    check_encryption_key
    
    # 3. 查找最新的 Release
    LATEST_RELEASE=$(find_latest_release)
    
    # 4. 下载 Release 文件
    download_release_files "$LATEST_RELEASE"
    
    # 5. 解压 + 解密
    extract_and_decrypt
    
    # 6. 验证文件
    verify_files
    
    # 7. 清理临时文件
    cleanup_temp_files
    
    echo ""
    log_success "=========================================="
    log_success "  恢复完成！"
    log_success "=========================================="
    echo ""
    log_info "已恢复文件："
    log_info "  - ark.tar"
    log_info "  - data.tar"
    echo ""
}

# 执行主函数
main
