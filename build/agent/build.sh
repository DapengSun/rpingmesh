#!/bin/bash
set -e

# Agent 独立构建脚本
IMAGE_NAME="rpingmesh-agent"
TAG="latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${BUILD_ROOT}/.." && pwd)"
SRC_ROOT="${PROJECT_ROOT}/src/rpingmesh"

if [ ! -d "${SRC_ROOT}" ]; then
    echo "未找到源码目录: ${SRC_ROOT}"
    exit 1
fi

echo "构建 R-Pingmesh Agent 镜像..."
echo "构建目录: ${BUILD_DIR}"

echo "1. 构建Agent二进制文件与eBPF..."

docker run --rm \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace/src/rpingmesh \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        apt-get update && apt-get install -y --fix-missing \
            git ca-certificates \
            libibverbs-dev librdmacm-dev \
            clang llvm libbpf-dev libelf-dev linux-headers-generic && \
        LLVM_STRIP_BIN=\"\$(command -v llvm-strip || command -v llvm-strip-18 || command -v llvm-strip-17 || command -v llvm-strip-16 || command -v llvm-strip-15 || command -v llvm-strip-14 || command -v llvm-strip-13 || command -v llvm-strip-12 || command -v llvm-strip-11)\" && \
        if [ -z \"\$LLVM_STRIP_BIN\" ]; then \
            LLVM_STRIP_CANDIDATE=\"\$(ls /usr/lib/llvm-*/bin/llvm-strip 2>/dev/null | head -n 1)\"; \
            if [ -n \"\$LLVM_STRIP_CANDIDATE\" ]; then \
                ln -sf \"\$LLVM_STRIP_CANDIDATE\" /usr/local/bin/llvm-strip; \
                LLVM_STRIP_BIN=\"/usr/local/bin/llvm-strip\"; \
            fi; \
        fi && \
        go mod download && \
        cd internal/ebpf && \
        if [ -z \"\$LLVM_STRIP_BIN\" ]; then \
            LLVM_STRIP_BIN=\"\$(command -v llvm-strip || command -v llvm-strip-18 || command -v llvm-strip-17 || command -v llvm-strip-16 || command -v llvm-strip-15 || command -v llvm-strip-14 || command -v llvm-strip-13 || command -v llvm-strip-12 || command -v llvm-strip-11)\"; \
        fi && \
        if [ -z \"\$LLVM_STRIP_BIN\" ]; then \
            echo \"未找到 llvm-strip，可通过安装 llvm (>=11) 包来提供该工具\"; \
            exit 1; \
        fi && \
        BPF2GO_LLVM_STRIP=\"\$LLVM_STRIP_BIN\" go generate ./... && \
        cd /workspace/src/rpingmesh && \
        CGO_ENABLED=1 go build -o /workspace/build/agent/build/agent ./cmd/agent
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


