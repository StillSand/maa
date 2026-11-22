#!/bin/bash
# 环境准备脚本

echo "准备运行环境..."
echo ""

# 更新系统（必须先完成）
echo "[1/4] 更新系统软件包列表..."
if timeout 120 sudo apt update > /dev/null 2>&1; then
    echo "✓ 系统软件包列表更新完成"
else
    echo "! 系统软件包列表更新失败（非致命错误）"
fi

# 并行执行：安装依赖 + 安装 docker-squash
echo "[2/4] 并行安装依赖..."
echo "    同时进行：系统依赖、docker-squash"
echo ""

(
    # 注意：linux-modules-extra 必须单独装。新 runner 内核（如 7.0.0-1017-azure）
    # 没有对应包，如果和 adb 写在同一条 apt 命令里，apt 会整条失败回滚，
    # 导致 adb 静默缺失，后续容器启动检查永远失败。
    echo "  → 尝试安装内核模块包（可选）..."
    if timeout 120 sudo apt install -y linux-modules-extra-$(uname -r) > /dev/null 2>&1; then
        echo "  ✓ 内核模块包安装完成"
    else
        echo "  i 当前内核无 linux-modules-extra 包，跳过（不影响运行）"
    fi

    echo "  → 安装系统依赖（python3, adb）..."
    if timeout 300 sudo apt install -y python3-requests python3-toml adb > /dev/null 2>&1; then
        echo "  ✓ 系统依赖安装完成"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "  ✗ 系统依赖安装超时（5分钟）"
        else
            echo "  ✗ 系统依赖安装失败"
        fi
    fi
) &
APT_PID=$!

(
    echo "  → 安装 docker-squash..."
    if timeout 120 pip3 install docker-squash > /dev/null 2>&1; then
        echo "  ✓ docker-squash 安装完成"
    else
        echo "  ! docker-squash 安装失败（可能已安装）"
    fi
) &

# 等待所有后台任务完成，显示进度
echo ""
echo "  等待安装完成..."
WAIT_COUNT=0
while kill -0 $APT_PID 2>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "  已等待 ${WAIT_COUNT} 秒..."
    fi
    sleep 1
done

wait

echo ""
echo "[2.5/4] 校验关键依赖..."

# adb 是容器就绪检测的命脉，缺失会导致 setup_container.sh 必然超时
if ! command -v adb > /dev/null 2>&1; then
    echo "✗ adb 未安装，容器启动检查无法进行"
    echo "   请检查上方 apt 安装日志"
    exit 1
fi
echo "✓ adb: $(adb version | head -1)"

if ! command -v docker > /dev/null 2>&1; then
    echo "✗ docker 不可用"
    exit 1
fi
echo "✓ docker: $(docker --version)"

echo ""
echo "[3/4] 加载 Android 内核模块（binder）..."

# 尝试加载 binder_linux 模块
if sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>/dev/null; then
    echo "✓ binder_linux 模块加载成功"
else
    echo "! binder_linux 模块加载失败，尝试检查是否已内置..."
    
    # 检查 binder 是否已经可用（可能内置在内核中）
    if [ -c /dev/binderfs/binder ] || [ -c /dev/binder ]; then
        echo "✓ binder 设备已存在（内核内置）"
    elif lsmod | grep -q binder; then
        echo "✓ binder 模块已加载"
    else
        echo "! 警告：binder 不可用，容器可能无法正常工作"
        echo "   内核版本: $(uname -r)"
        echo "   可用模块: $(ls /lib/modules/$(uname -r)/kernel/drivers/ 2>/dev/null | grep -i android || echo '无')"
    fi
fi

echo ""
echo "[4/4] 检查安装结果..."
echo "✓ 环境准备完成"
echo ""
