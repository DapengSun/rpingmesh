#!/bin/bash

# Controller 独立构建脚本
set -e

IMAGE_NAME="rpingmesh-controller"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

echo "构建 R-Pingmesh Controller 镜像..."
echo "构建目录: ${BUILD_DIR}"

echo "1. 构建Controller二进制文件..."

docker run --rm \
    -v "${REPO_ROOT}:/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates &&
        go mod download &&
        go build -o /workspace/controller-build/build/controller ./cmd/controller
    "

# 2. 构建Controller镜像

echo "2. 构建Controller镜像..."
cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Controller镜像构建完成！"

echo
echo "镜像信息:"

docker images "$IMAGE_NAME:$TAG"

echo
echo "=== Controller使用方法 ==="

echo
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > controller.tar.gz"

echo
echo "2. 在目标平台加载:"
echo "   docker load < controller.tar.gz"

echo
echo "3. 创建配置文件:"
echo "   mkdir -p /path/to/your/config"
echo "   cat > /path/to/your/config/controller.yaml << 'EOF'"
echo "   listen-addr: \"0.0.0.0:50051\""
echo "   database-uri: \"http://rqlite:4001\""
echo "   log-level: \"info\""
echo "   EOF"

echo
echo "4. 启动Controller (使用volume挂载):"
echo "   docker run -d \\\n     --name controller \\\n     --network rpingmesh-network \\\n     -p 50051:50051 \\\n     -p 2222:22 \\\n     -v /path/to/your/config:/app/config:ro \\\n     $IMAGE_NAME:$TAG"

echo
echo "   说明:"
echo "   - /path/to/your/config: 宿主机配置文件目录 (包含controller.yaml)"
echo "   - /app/config: 容器内配置文件目录 (固定路径)"
echo "   - :ro 表示只读挂载"
echo "   - 重要: 只挂载config目录，不要挂载整个/app目录"

echo
echo "5. SSH登录容器:"
echo "   ssh root@localhost -p 2222"
echo "   密码: rpingmesh"

echo
echo "6. 管理Controller:"
echo "   # SSH登录容器"
echo "   ssh root@localhost -p 2222"
echo "   # 密码: rpingmesh"

echo
echo "   # 手动启动Controller（在容器内）"
echo "   /app/controller --config /app/config/controller.yaml &"

echo
echo "   # 查看状态"
echo "   docker exec controller /app/status.sh"
echo "   # 或通过SSH"
echo "   ssh root@localhost -p 2222 '/app/status.sh'"

echo
echo "   # 查看进程"
echo "   docker exec controller ps aux | grep controller"

echo
echo "   # 停止服务"
echo "   docker stop controller"

echo
echo "7. 目录映射说明:"
echo "   容器内固定路径: /app"
echo "   - 配置文件: /app/config/controller.yaml"
echo "   - 二进制文件: /app/controller"
echo "   - 启动脚本: /app/start.sh"
echo "   - 状态脚本: /app/status.sh"

echo
echo "   宿主机路径可以任意指定，通过 -v 参数映射到容器内 /app 目录"
