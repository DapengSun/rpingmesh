#!/bin/bash
set -e

echo "启动 R-Pingmesh Controller..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/controller"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

mkdir -p "$PERSISTENT_DATA_DIR"
mkdir -p "$PERSISTENT_CONFIG_DIR"

# 验证配置文件是否已挂载
if [ ! -f "$PERSISTENT_CONFIG_DIR/controller.yaml" ]; then
    echo "错误: 配置文件 $PERSISTENT_CONFIG_DIR/controller.yaml 不存在"
    echo "请确保配置文件已正确挂载到容器中"
    echo "检查挂载点: $PERSISTENT_CONFIG_DIR"
    ls -la "$PERSISTENT_CONFIG_DIR" 2>&1 || echo "目录不存在"
    exit 1
fi

# 创建软链接：/app/data -> /private/rpingmesh/controller/data
if [ -L "/app/data" ] || [ -e "/app/data" ]; then
    rm -rf "/app/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/app/data"

# 创建软链接：/app/config -> /private/rpingmesh/controller/config
if [ -L "/app/config" ] || [ -e "/app/config" ]; then
    rm -rf "/app/config"
fi
ln -sf "$PERSISTENT_CONFIG_DIR" "/app/config"

if [ ! -f "/app/config/controller.yaml" ]; then
    echo "错误: 配置文件 /app/config/controller.yaml 不存在（软链接后检查）"
    echo "配置目录内容:"
    ls -la "$PERSISTENT_CONFIG_DIR" 2>&1
    echo "软链接目标:"
    readlink -f /app/config 2>&1 || echo "软链接无效"
    exit 1
fi

echo "配置文件检查通过"
echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2
echo "启动 Supervisor..."

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
