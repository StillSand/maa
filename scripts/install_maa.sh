#!/bin/bash
# MAA 安装脚本

echo "安装 MAA..."
echo ""

# 获取最新版本
echo "[1/6] 获取最新版本信息..."
MAA_VERSION=$(curl -s https://api.github.com/repos/MaaAssistantArknights/maa-cli/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

# 如果无法获取最新版本，使用默认版本
if [ -z "$MAA_VERSION" ]; then
    echo "! 无法获取最新版本，使用默认版本 v0.6.0"
    MAA_VERSION="v0.6.0"
else
    echo "✓ 最新版本: $MAA_VERSION"
fi
echo ""

# 下载 maa-cli
echo " [2/6] 下载 maa-cli..."
echo "    文件: maa_cli-${MAA_VERSION}-aarch64-unknown-linux-gnu.tar.gz"
echo "    这可能需要 30-60 秒..."

if wget --show-progress https://github.com/MaaAssistantArknights/maa-cli/releases/download/${MAA_VERSION}/maa_cli-${MAA_VERSION}-aarch64-unknown-linux-gnu.tar.gz 2>&1 | grep -E '(saved|100%)'; then
    echo "✓ 下载完成"
else
    echo "✗ maa-cli 下载失败"
    exit 1
fi
echo ""

# 解压
echo "[3/6] 解压 maa-cli..."
if tar -xzf maa_cli-${MAA_VERSION}-aarch64-unknown-linux-gnu.tar.gz; then
    rm maa_cli-${MAA_VERSION}-aarch64-unknown-linux-gnu.tar.gz
    echo "✓ 解压完成"
else
    echo "✗ 解压失败"
    exit 1
fi
echo ""

# 安装
echo "[4/6] 安装 maa 到系统..."
mv maa /usr/local/bin
chmod +x /usr/local/bin/maa
echo "✓ 安装完成"
echo ""

# 复制配置
echo " [5/6] 复制配置文件..."
cp -r .config ~
echo "✓ 配置文件已复制"
echo ""

# 更新 maa-cli
echo "↻ [5.5/6] 更新 maa-cli..."
if maa self update; then
    echo "✓ maa-cli 更新完成"
else
    echo "! maa-cli 更新失败（可能已是最新版本）"
fi
echo ""

# 安装 MaaCore 和资源
echo "[6/6] 安装 MaaCore 和资源文件..."
echo "    这可能需要 2-5 分钟，请耐心等待..."
echo "    提示：你会看到下载进度条，这是正常的"
echo ""

if maa install; then
    echo ""
    echo "✓ MaaCore 安装完成"
else
    echo ""
    echo "✗ MaaCore 安装失败"
    exit 1
fi
echo ""

# 更新资源
echo "↻ 更新资源文件..."
if maa update; then
    echo "✓ 资源更新完成"
else
    echo "! 资源更新失败，但可以继续使用"
fi
echo ""

# 验证安装
echo "✓ 验证安装..."
if maa version > /dev/null 2>&1; then
    echo "✓ MAA 安装完成"
    echo ""
    echo "版本信息："
    maa version
else
    echo "✗ MAA 安装验证失败"
    exit 1
fi
echo ""
