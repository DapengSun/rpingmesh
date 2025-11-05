#!/bin/bash
set -e

echo "启动 R-Pingmesh OpenTelemetry Collector..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/otel-collector"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"

# 创建软链接：/app/data -> /private/rpingmesh/otel-collector/data
if [ -L "/app/data" ] || [ -e "/app/data" ]; then
    rm -rf "/app/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/app/data"

# 创建 storage 子目录（用于 file_storage extension）
mkdir -p "/app/data/storage"

# 创建软链接：/app/config -> /private/rpingmesh/otel-collector/config
if [ -L "/app/config" ] || [ -e "/app/config" ]; then
    rm -rf "/app/config"
fi
ln -sf "$PERSISTENT_CONFIG_DIR" "/app/config"

# 检查配置文件是否存在，如果不存在则从示例创建
CONFIG_FILE="/app/config/otel-collector-config.yaml"
EXAMPLE_CONFIG="/usr/local/share/otel-collector-config.yaml.example"

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$EXAMPLE_CONFIG" ]; then
        cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
    else
        echo "错误: 示例配置文件不存在: $EXAMPLE_CONFIG"
        exit 1
    fi
fi

# 验证 otelcol 二进制文件
if [ ! -f "/usr/local/bin/otelcol" ]; then
    echo "错误: OpenTelemetry Collector 二进制文件不存在"
    exit 1
fi

# 启动SSH服务
/etc/init.d/ssh-start &
sleep 2

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
