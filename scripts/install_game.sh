#!/bin/bash
# 游戏安装脚本

CLIENT_TYPE="$1"

echo "安装/更新游戏..."
echo ""

# 下载游戏 APK
echo " [1/3] 下载 ${CLIENT_TYPE} 版本游戏..."
echo "    这可能需要 3-10 分钟，取决于网络速度..."
echo ""

if python3 download.py "${CLIENT_TYPE}"; then
    echo ""
    echo "✓ 下载完成"
else
    echo ""
    echo "✗ 游戏下载失败"
    exit 1
fi
echo ""

# 检查下载是否成功
if [ ! -f arknights.apk ]; then
    echo "✗ 游戏 APK 文件不存在"
    exit 1
fi

# 显示 APK 文件大小
APK_SIZE=$(du -h arknights.apk | cut -f1)
echo "APK 文件大小: $APK_SIZE"
echo ""

# 连接 ADB
echo "[2/3] 连接 ADB..."
if adb kill-server && adb connect 127.0.0.1:5555 > /dev/null 2>&1; then
    echo "✓ ADB 连接成功"
    echo ""
    echo "设备列表："
    adb devices
else
    echo "✗ ADB 连接失败"
    rm arknights.apk
    exit 1
fi
echo ""

# 安装游戏（使用 -r 参数保留数据）
echo "[3/3] 安装游戏到设备..."
echo "    使用 -r 参数保留游戏数据"
echo "    这可能需要 1-3 分钟..."
echo ""

if adb -s 127.0.0.1:5555 install -r arknights.apk 2>&1 | tee /tmp/install.log; then
    echo ""
    echo "✓ 游戏安装成功"
else
    echo ""
    echo "✗ 游戏安装失败"
    echo "错误日志："
    cat /tmp/install.log
    rm arknights.apk
    exit 1
fi

# 清理 APK 文件
rm arknights.apk
rm -f /tmp/install.log

echo ""
echo "✓ 游戏安装完成"
echo ""
