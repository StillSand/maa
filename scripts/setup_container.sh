#!/bin/bash
# 容器设置脚本

echo "启动 Android 容器..."
echo ""

if ! command -v adb > /dev/null 2>&1; then
    echo "✗ adb 未安装，无法检测容器启动状态"
    exit 1
fi

# 检查是否强制使用默认镜像
if [[ "${USE_DEFAULT_IMAGE}" == "true" ]]; then
    echo "! 强制使用默认镜像模式"
    echo "   跳过加载已保存的容器"
    echo ""
    # 删除已保存的容器文件（如果存在）
    rm -f ./ark.tar ./data.tar 2>/dev/null || true
    sudo rm -rf ./data 2>/dev/null || true
elif [[ -f ./ark.tar ]] && [[ -f ./data.tar ]]; then
    echo "发现已保存的容器文件"
    
    ARK_SIZE=$(du -h ./ark.tar | cut -f1)
    DATA_SIZE=$(du -h ./data.tar | cut -f1)
    echo "   - ark.tar: $ARK_SIZE"
    echo "   - data.tar: $DATA_SIZE"
    
    echo "加载 Docker 镜像（这可能需要 30-60 秒）..."
    if docker load -i ./ark.tar > /dev/null 2>&1; then
        echo "✓ Docker 镜像加载完成"
    else
        echo "✗ Docker 镜像加载失败"
        exit 1
    fi
    
    sudo rm ./ark.tar
    export IMAGETAG=ark
    
    echo "解压数据文件（这可能需要 10-20 秒）..."
    if sudo tar -xf ./data.tar > /dev/null 2>&1; then
        echo "✓ 数据文件解压完成"
    else
        echo "✗ 数据文件解压失败"
        exit 1
    fi
    
    sudo rm ./data.tar
    echo "✓ 容器文件加载完成"
    echo ""
else
    echo "i 未发现已保存的容器，将使用默认镜像"
    echo ""
fi

# 启动容器
echo "启动 Docker 容器..."
if docker compose up -d > /dev/null 2>&1; then
    echo "✓ Docker 容器已启动"
else
    echo "✗ Docker 容器启动失败"
    exit 1
fi

# 等待容器就绪
MAX_ATTEMPTS=${1:-180}  # 默认 180 次尝试
attempt=0

echo ""
echo "等待 Android 系统启动（最多 ${MAX_ATTEMPTS} 次尝试）..."
echo "   提示：首次启动可能需要 1-2 分钟"
echo ""

while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
    # 每次循环都重新连接 ADB（这是必要的，因为 redroid 的 ADB 守护进程是异步初始化的）
    adb kill-server > /dev/null 2>&1
    adb connect 127.0.0.1:5555 > /dev/null 2>&1
    
    # 检查容器是否还在运行
    if ! docker ps | grep -q redroid; then
        echo ""
        echo "✗ Docker 容器已停止运行"
        echo "容器日志："
        docker logs redroid 2>&1 | tail -20
        exit 1
    fi
    
    # 检查 Android 系统是否启动完成
    BOOT_STATUS=$(adb -s 127.0.0.1:5555 shell getprop sys.boot_completed 2>/dev/null || echo "0")
    
    if [[ "$BOOT_STATUS" == "1" ]]; then
        echo ""
        echo "✓ Android 容器已就绪（尝试 ${attempt} 次，约 ${attempt} 秒）"
        echo ""
        
        # 显示 Android 版本信息
        ANDROID_VERSION=$(adb -s 127.0.0.1:5555 shell getprop ro.build.version.release 2>/dev/null || echo "未知")
        echo "Android 版本: ${ANDROID_VERSION}"
        echo ""
        exit 0
    fi
    
    # 每 10 次尝试显示一次进度（约每 10 秒）
    if [ $((attempt % 10)) -eq 0 ] && [ $attempt -gt 0 ]; then
        echo "   已尝试 ${attempt}/${MAX_ATTEMPTS} 次（约 ${attempt} 秒）..."
        
        # 显示调试信息
        if [ $((attempt % 30)) -eq 0 ]; then
            echo "   调试信息："
            echo "      - 容器状态: $(docker ps --filter name=redroid --format '{{.Status}}' 2>/dev/null || echo '未知')"
            echo "      - ADB 连接: $(adb devices 2>/dev/null | grep 127.0.0.1:5555 || echo '未连接')"
            echo "      - boot_completed: ${BOOT_STATUS}"
        fi
    fi
    
    attempt=$((attempt + 1))
    sleep 1
done

echo ""
echo "✗ 容器启动超时（超过 ${MAX_ATTEMPTS} 次尝试）"
echo ""
echo "最终状态："
echo "   - 容器状态: $(docker ps --filter name=redroid --format '{{.Status}}' 2>/dev/null || echo '未知')"
echo "   - ADB 设备: $(adb devices 2>/dev/null | grep -v 'List of devices' || echo '无设备')"
echo ""
echo "容器日志（最后 30 行）："
docker logs redroid 2>&1 | tail -30
exit 1
