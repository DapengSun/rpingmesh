#!/bin/bash
# Use set -e for critical operations, but allow graceful handling of /data directory setup
set -e

echo "启动 R-Pingmesh RQLite..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/rqlite"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR"

# 设置 /data 目录：如果是挂载点则直接使用，否则创建软链接
if mountpoint -q "/data" 2>/dev/null; then
    # 挂载点存在，直接使用
    PERSISTENT_DATA_DIR="/data"
    echo "信息: /data 是挂载点，直接使用"
else
    # 不是挂载点，尝试创建软链接
    if [ -e "/data" ] && [ ! -L "/data" ]; then
        # 如果存在且不是软链接，尝试删除（忽略错误）
        rm -rf "/data" 2>/dev/null || true
    fi
    # 创建软链接，失败则使用 /data 目录
    if ln -sf "$PERSISTENT_DATA_DIR" "/data" 2>/dev/null; then
        echo "信息: 已创建软链接 /data -> $PERSISTENT_DATA_DIR"
    else
        PERSISTENT_DATA_DIR="/data"
        mkdir -p "$PERSISTENT_DATA_DIR"
        echo "警告: 无法创建软链接，直接使用 /data 目录"
    fi
fi

# 设置节点ID
export NODE_ID=${NODE_ID:-"rqlite-$(hostname)"}

echo "节点ID: $NODE_ID"
echo "数据目录: /data -> $PERSISTENT_DATA_DIR"
echo "HTTP地址: 0.0.0.0:4001"
echo "Raft地址: 0.0.0.0:4002"

# 如果设置了JOIN_ADDR，则加入集群
if [ -n "$JOIN_ADDR" ]; then
    echo "加入集群: $JOIN_ADDR"
    export JOIN_ADDR
else
    echo "启动单节点模式"
    unset JOIN_ADDR
fi

echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2

echo "启动 Supervisor..."
# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
