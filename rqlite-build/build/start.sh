#!/bin/bash
set -e

echo "启动 R-Pingmesh RQLite..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/rqlite"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR"

# 创建软链接：/data -> /private/rpingmesh/rqlite/data
if [ -L "/data" ] || [ -e "/data" ]; then
    rm -rf "/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/data"

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
