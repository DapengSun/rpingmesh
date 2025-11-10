#!/bin/bash
set -e

echo "启动 R-Pingmesh Analyzer..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/analyzer"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"

# 检查配置文件是否已挂载（通过 bind mount）
CONFIG_FILE="$PERSISTENT_CONFIG_DIR/analyzer.yaml"
CONFIG_SOURCE="/mnt/config-source/analyzer.yaml"

# 如果配置文件源存在（通过 bind mount 挂载），则复制到持久化目录（仅当目标文件不存在时）
if [ -f "$CONFIG_SOURCE" ] && [ -s "$CONFIG_SOURCE" ]; then
    echo "信息: 检测到配置文件源: $CONFIG_SOURCE"
    if [ ! -f "$CONFIG_FILE" ]; then
        # 目标文件不存在，复制配置文件到持久化目录
        cp "$CONFIG_SOURCE" "$CONFIG_FILE"
        echo "信息: 已将配置文件复制到持久化目录: $CONFIG_FILE"
    else
        # 目标文件已存在，不覆盖
        echo "信息: 配置文件已存在，跳过复制: $CONFIG_FILE"
        if [ ! -s "$CONFIG_FILE" ]; then
            echo "警告: 配置文件存在但为空: $CONFIG_FILE"
            echo "请检查配置文件是否正确"
        fi
    fi
elif [ -f "$CONFIG_FILE" ]; then
    # 如果持久化目录中已有配置文件，检查是否有内容
    if [ -s "$CONFIG_FILE" ]; then
        echo "信息: 使用持久化目录中的配置文件: $CONFIG_FILE"
    else
        echo "警告: 配置文件存在但为空: $CONFIG_FILE"
        echo "请检查配置文件是否正确"
    fi
else
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    echo "请确保配置文件已正确挂载或复制到容器中"
    echo "检查挂载点: $PERSISTENT_CONFIG_DIR"
    ls -la "$PERSISTENT_CONFIG_DIR" 2>&1 || echo "目录不存在"
    exit 1
fi

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
