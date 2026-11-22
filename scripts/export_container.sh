#!/bin/bash
# 容器导出脚本

echo "保存容器状态..."
echo ""

# 卸载游戏（保留数据）
echo "[1/6] 卸载游戏（保留数据）..."
adb kill-server > /dev/null 2>&1
adb connect 127.0.0.1:5555 > /dev/null 2>&1
if adb -s 127.0.0.1:5555 shell cmd package uninstall -k com.hypergryph.arknights > /dev/null 2>&1; then
    echo "✓ 游戏已卸载（数据已保留）"
else
    echo "i 游戏可能未安装或已卸载"
fi

# 停止并提交容器
echo "[2/6] 停止 Docker 容器..."
if docker stop redroid > /dev/null 2>&1; then
    echo "✓ 容器已停止"
else
    echo "! 容器停止失败（可能未运行）"
fi

echo "[3/6] 提交容器更改（这可能需要 10-30 秒）..."
if docker commit redroid ark > /dev/null 2>&1; then
    echo "✓ 容器更改已提交"
else
    echo "✗ 容器提交失败"
    exit 1
fi

docker rm redroid > /dev/null 2>&1
docker rmi redroid/redroid:11.0.0-latest 2>/dev/null || :

# 优化容器镜像
echo " [4/6] 优化容器镜像（合并镜像层，这可能需要 1-2 分钟）..."
if docker-squash -t ark ark > /dev/null 2>&1; then
    echo "✓ 容器镜像已优化"
else
    echo "! 容器优化失败（将使用未优化版本）"
fi

# 保存容器
echo "[5/6] 导出容器镜像到 ark.tar（这可能需要 30-60 秒）..."
if docker save ark -o ./ark.tar; then
    ARK_SIZE=$(du -h ./ark.tar | cut -f1)
    echo "✓ 容器镜像已导出（大小: $ARK_SIZE）"
else
    echo "✗ 容器导出失败"
    exit 1
fi

docker rmi ark > /dev/null 2>&1

# 保存数据
echo "[6/6] 打包数据文件到 data.tar（这可能需要 1-2 分钟）..."
if sudo tar -cpf ./data.tar data > /dev/null 2>&1; then
    DATA_SIZE=$(du -h ./data.tar | cut -f1)
    echo "✓ 数据文件已打包（大小: $DATA_SIZE）"
else
    echo "✗ 数据打包失败"
    exit 1
fi

sudo rm -rf data

echo ""
echo "✓ 容器状态已保存"
echo "   - ark.tar: $(du -h ./ark.tar | cut -f1)"
echo "   - data.tar: $(du -h ./data.tar | cut -f1)"
echo ""
