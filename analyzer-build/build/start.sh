#!/bin/bash
set -e

echo "启动 R-Pingmesh Analyzer..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/analyzer"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"

# 创建软链接：/app/data -> /private/rpingmesh/analyzer/data
if [ -L "/app/data" ] || [ -e "/app/data" ]; then
    rm -rf "/app/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/app/data"

# 创建软链接：/app/config -> /private/rpingmesh/analyzer/config
if [ -L "/app/config" ] || [ -e "/app/config" ]; then
    rm -rf "/app/config"
fi
ln -sf "$PERSISTENT_CONFIG_DIR" "/app/config"

# 环境变量设置
: ${LISTEN_ADDR:=0.0.0.0:50052}
export LISTEN_ADDR

if [ -z "$DATABASE_URI" ]; then
  echo "[analyzer] Warning: DATABASE_URI is empty; set -e DATABASE_URI=http://rqlite:4001 if using rqlite in same network"
else
  echo "[analyzer] DATABASE_URI=$DATABASE_URI"
fi

echo "[analyzer] LISTEN_ADDR=$LISTEN_ADDR"

# 检查配置文件（如果使用配置文件模式）
if [ -n "$CONFIG_FILE" ] || [ -f "/app/config/analyzer.yaml" ]; then
    CONFIG_FILE="${CONFIG_FILE:-/app/config/analyzer.yaml}"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误: 配置文件 $CONFIG_FILE 不存在"
        echo "请确保配置文件已正确挂载到容器中"
        ls -R /app
        exit 1
    fi
    echo "配置文件检查通过: $CONFIG_FILE"
fi

# 启动SSH服务
echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2

echo "启动 Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
