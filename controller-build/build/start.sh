#!/bin/bash
set -e

echo "启动 R-Pingmesh Controller..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/controller"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"

# 创建软链接：/app/data -> /private/rpingmesh/controller/data
if [ -L "/app/data" ] || [ -e "/app/data" ]; then
    rm -rf "/app/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/app/data"

# 创建软链接：/app/config -> /private/rpingmesh/controller/config
if [ -L "/app/config" ] || [ -e "/app/config" ]; then
    rm -rf "/app/config"d
fi
ln -sf "$PERSISTENT_CONFIG_DIR" "/app/config"

# 检查配置文件
if [ ! -f "/app/config/controller.yaml" ]; then
    echo "错误: 配置文件 /app/config/controller.yaml 不存在"
    echo "请确保配置文件已正确挂载到容器中"
    ls -R /app
    exit 1
fi

echo "配置文件检查通过"
echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2
echo "启动 Supervisor..."

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
