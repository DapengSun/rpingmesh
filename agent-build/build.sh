#!/bin/bash
set -e

# Agent 独立构建脚本（与 controller-build 对齐）
IMAGE_NAME="rpingmesh-agent"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

echo "构建 R-Pingmesh Agent 镜像..."
echo "构建目录: ${BUILD_DIR}"

echo "1. 构建Agent二进制文件与eBPF..."

docker run --rm \
    -v "${REPO_ROOT}:/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        apt-get update && apt-get install -y --fix-missing \
            git ca-certificates \
            libibverbs-dev librdmacm-dev \
            clang llvm libbpf-dev libelf-dev linux-headers-generic && \
        go mod download && \
        CGO_ENABLED=1 go build -o /workspace/agent-build/build/agent ./cmd/agent && \
        cd /workspace/internal/ebpf && go generate ./...
    "

# 2. 构建Agent镜像

echo "2. 构建Agent镜像..."
cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Agent镜像构建完成！"

echo
echo "镜像信息:"

docker images "$IMAGE_NAME:$TAG"

echo
echo "=== Agent使用方法 ==="

echo
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > agent.tar.gz"

echo
echo "2. 在目标平台加载:"
echo "   docker load < agent.tar.gz"

echo
echo "3. 创建配置文件:"
echo "   mkdir -p /path/to/your/config"
echo "   cat > /path/to/your/config/agent.yaml << 'EOF'"
echo "   controller-addr: \"controller:50051\""
echo "   analyzer-addr: \"127.0.0.1:50052\""
echo "   log-level: \"info\""
echo "   probe-interval-ms: 500"
echo "   ebpf-enabled: true"
echo "   EOF"

echo
echo "4. 启动Agent:"
echo "   docker run -d \\" \
     " --name agent \\" \
     " --privileged \\" \
     " --network rpingmesh-network \\" \
     " -e RPINGMESH_CONTROLLER_ADDR=10.81.1.240:50051 \\" \
     " -e RPINGMESH_ANALYZER_ADDR=10.81.1.240:50052 \\" \
     " -v /path/to/your/config:/app/config:ro \\" \
     " -p 2223:22 \\" \
     " $IMAGE_NAME:$TAG"

echo
echo "5. SSH登录容器:"
echo "   ssh root@localhost -p 2223"
echo "   密码: rpingmesh"

echo
echo "6. 管理Agent:"
echo "   # 容器内查看状态"
echo "   docker exec agent /app/status.sh"
echo "   # 或通过SSH"
echo "   ssh root@localhost -p 2223 '/app/status.sh'"

echo
echo "7. 目录说明:"
echo "   容器内固定路径: /app"
echo "   - 配置文件: /app/config/agent.yaml"
echo "   - 二进制文件: /usr/local/bin/agent"
echo "   - 启动脚本: /usr/local/bin/start.sh"
echo "   - 状态脚本: /app/status.sh"


