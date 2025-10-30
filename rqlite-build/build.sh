#!/bin/bash

# RQLite 独立构建脚本
set -e

IMAGE_NAME="rpingmesh-rqlite"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

echo "构建 R-Pingmesh RQLite 镜像..."
echo "构建目录: ${BUILD_DIR}"

# 1. 构建RQLite镜像
echo "1. 构建RQLite镜像..."
cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "RQLite镜像构建完成！"
echo
echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"

echo
echo "=== RQLite使用方法 ==="
echo
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > rqlite.tar.gz"
echo
echo "2. 在目标平台加载:"
echo "   docker load < rqlite.tar.gz"
echo
echo "3. 启动RQLite (单节点):"
echo "   docker run -d \\"
echo "     --name rqlite \\"
echo "     --network rpingmesh-network \\"
echo "     -p 4001:4001 \\"
echo "     -p 4002:4002 \\"
echo "     -p 2222:22 \\"
echo "     -v \$(pwd)/data:/data \\"
echo "     -e NODE_ID=rqlite-001 \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "4. 启动RQLite集群 (3节点示例):"
echo "   # 节点1 (Leader)"
echo "   docker run -d \\"
echo "     --name rqlite-1 \\"
echo "     --network rpingmesh-network \\"
echo "     -p 4001:4001 \\"
echo "     -p 4002:4002 \\"
echo "     -v \$(pwd)/data1:/data \\"
echo "     -e NODE_ID=rqlite-1 \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "   # 节点2 (Follower)"
echo "   docker run -d \\"
echo "     --name rqlite-2 \\"
echo "     --network rpingmesh-network \\"
echo "     -p 4003:4001 \\"
echo "     -p 4004:4002 \\"
echo "     -v \$(pwd)/data2:/data \\"
echo "     -e NODE_ID=rqlite-2 \\"
echo "     -e JOIN_ADDR=rqlite-1:4002 \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "   # 节点3 (Follower)"
echo "   docker run -d \\"
echo "     --name rqlite-3 \\"
echo "     --network rpingmesh-network \\"
echo "     -p 4005:4001 \\"
echo "     -p 4006:4002 \\"
echo "     -v \$(pwd)/data3:/data \\"
echo "     -e NODE_ID=rqlite-3 \\"
echo "     -e JOIN_ADDR=rqlite-1:4002 \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "5. SSH登录容器:"
echo "   ssh root@localhost -p 2222"
echo "   密码: rpingmesh"
echo
echo "6. 管理RQLite:"
echo "   # SSH登录容器"
echo "   ssh root@localhost -p 2222"
echo "   # 密码: rpingmesh"
echo
echo "   # 查看状态"
echo "   docker exec rqlite /usr/local/bin/status.sh"
echo "   # 或通过SSH"
echo "   ssh root@localhost -p 2222 '/usr/local/bin/status.sh'"
echo
echo "   # 查看日志"
echo "   docker exec rqlite tail -f /var/log/supervisor/rqlite.log"
echo
echo "   # 重启服务"
echo "   docker exec rqlite supervisorctl restart rqlite"
echo
echo "   # 健康检查"
echo "   curl http://localhost:4001/status"
echo
echo "   # 停止服务"
echo "   docker stop rqlite"
echo
echo "7. 目录映射说明:"
echo "   容器内固定路径: /data"
echo "   - 数据目录: /data"
echo "   - 二进制文件: /usr/local/bin/rqlited, /usr/local/bin/rqlite"
echo "   - 启动脚本: /usr/local/bin/start.sh"
echo "   - 状态脚本: /usr/local/bin/status.sh"
echo
echo "   宿主机路径可以任意指定，通过 -v 参数映射到容器内 /data 目录"
echo
echo "8. 环境变量说明:"
echo "   - NODE_ID: RQLite节点ID (默认: rqlite-\$(hostname))"
echo "   - JOIN_ADDR: 加入集群的地址 (格式: hostname:raft-port)"
echo "   - HTTP_ADDR: HTTP监听地址 (默认: 0.0.0.0:4001)"
echo "   - RAFT_ADDR: Raft监听地址 (默认: 0.0.0.0:4002)"
