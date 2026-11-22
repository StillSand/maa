#!/bin/bash
# Cloudflare Tunnel 和 ws-scrcpy 设置脚本

# 从环境变量读取 token（更安全，不会出现在进程列表中）
CLOUDFLARE_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN}"
WS_PASSWORD="${WS_SCRCPY_PASSWORD}"
AUTH_USER="${WS_SCRCPY_USER:-maa}"

if [ -z "$CLOUDFLARE_TOKEN" ]; then
    echo "✗ 错误：未设置 CLOUDFLARE_TUNNEL_TOKEN 环境变量"
    exit 1
fi

echo "设置远程访问通道..."
echo ""

# 清理可能存在的旧容器
echo "[1/5] 清理旧容器..."
docker rm -f cloudflared ws-scrcpy scrcpy-auth > /dev/null 2>&1 || true
echo "✓ 清理完成"
echo ""

# 拉取 Cloudflare Tunnel 镜像
echo "[2/5] 拉取 Cloudflare Tunnel 镜像..."
echo "    镜像: cloudflare/cloudflared:latest"
if docker pull cloudflare/cloudflared:latest 2>&1 | grep -E '(Downloaded|up to date|Already exists)'; then
    echo "✓ 镜像准备完成"
else
    echo "! 镜像拉取可能失败，尝试继续..."
fi
echo ""

# 启动 Cloudflare Tunnel（使用 host 网络模式，避免容器网络隔离问题）
echo "[3/5] 启动 Cloudflare Tunnel..."
if docker run -d --name cloudflared --network host cloudflare/cloudflared:latest tunnel --no-autoupdate run --token "${CLOUDFLARE_TOKEN}" > /dev/null 2>&1; then
    echo "✓ Cloudflare Tunnel 已启动"
    echo "    容器名: cloudflared"
    echo "    网络模式: host"
else
    echo "✗ Cloudflare Tunnel 启动失败"
    exit 1
fi
echo ""

# ws-scrcpy 本身没有任何认证能力，必须经 nginx Basic Auth 暴露
if [ -z "$WS_PASSWORD" ]; then
    echo "[4/5] 未设置 WS_SCRCPY_PASSWORD，跳过 ws-scrcpy"
    echo "! 出于安全考虑，不启动远程控制页面"
    echo "! 如需使用，请在仓库 Secrets 中添加 WS_SCRCPY_PASSWORD"
    echo ""
    echo "✓ 远程访问通道已建立（仅隧道，无控制页面）"
    exit 0
fi

# 拉取 ws-scrcpy 镜像
echo "[4/5] 拉取 ws-scrcpy / nginx 镜像..."
echo "    镜像: haris132/ws-scrcpy, nginx:alpine"
if docker pull haris132/ws-scrcpy 2>&1 | grep -E '(Downloaded|up to date|Already exists)'; then
    echo "✓ ws-scrcpy 镜像准备完成"
else
    echo "! ws-scrcpy 镜像拉取可能失败，尝试继续..."
fi
if docker pull nginx:alpine 2>&1 | grep -E '(Downloaded|up to date|Already exists)'; then
    echo "✓ nginx 镜像准备完成"
else
    echo "! nginx 镜像拉取可能失败，尝试继续..."
fi
echo ""

# 启动 ws-scrcpy + nginx Basic Auth
echo "[5/5] 启动 ws-scrcpy（nginx Basic Auth 保护）..."
docker network create maa-net > /dev/null 2>&1 || true

if ! docker run --name ws-scrcpy -d --network maa-net \
    --add-host=host.docker.internal:host-gateway \
    haris132/ws-scrcpy > /dev/null 2>&1; then
    echo "✗ ws-scrcpy 启动失败"
    exit 1
fi
echo "✓ ws-scrcpy 已启动（仅内网，不对外发布端口）"

AUTH_DIR=/tmp/scrcpy-auth
mkdir -p "$AUTH_DIR"
printf '%s:%s\n' "$AUTH_USER" "$(openssl passwd -apr1 "$WS_PASSWORD")" > "$AUTH_DIR/.htpasswd"

cat > "$AUTH_DIR/default.conf" <<'NGINX'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name _;

    auth_basic           "MAA Remote";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://ws-scrcpy:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
NGINX

if docker run --name scrcpy-auth -d --network maa-net \
    -p 8000:80 \
    -v "$AUTH_DIR/default.conf:/etc/nginx/conf.d/default.conf:ro" \
    -v "$AUTH_DIR/.htpasswd:/etc/nginx/.htpasswd:ro" \
    nginx:alpine > /dev/null 2>&1; then
    echo "✓ nginx 已启动，端口 8000"
else
    echo "✗ nginx 启动失败"
    exit 1
fi
echo ""

# 连接 ADB
echo "连接 ADB 到容器..."
sleep 2  # 等待容器完全启动
if docker exec ws-scrcpy adb connect host.docker.internal:5555 > /dev/null 2>&1; then
    echo "✓ ADB 连接成功"
else
    echo "! ADB 连接失败（可能需要稍后重试）"
fi
echo ""

echo "✓ 远程访问通道已建立（已启用密码保护）"
echo ""
echo "容器状态："
docker ps --filter "name=cloudflared" --filter "name=ws-scrcpy" --filter "name=scrcpy-auth" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""