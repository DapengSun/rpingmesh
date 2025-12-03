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

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

if [ ! -d "${SRC_ROOT}" ]; then
    echo "未找到源码目录: ${SRC_ROOT}"
    exit 1
fi

echo "构建 R-Pingmesh Agent 镜像..."
echo "构建目录: ${BUILD_DIR}"
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

echo "1. 构建Agent二进制文件与eBPF..."
# 注意：Go 支持交叉编译，不需要使用 --platform，只需设置 GOARCH
# 这样可以避免 QEMU 模拟器在 apt-get 等操作时的段错误问题
# 注意：eBPF 代码生成可能需要在目标架构上运行，但 Go 编译可以使用交叉编译

# 判断是否需要生成 eBPF 代码（ARM64 架构跳过 eBPF 生成）
SKIP_EBPF=""
if [ "${TARGET_ARCH}" = "arm64" ]; then
    echo "  检测到 ARM64 架构，跳过 eBPF 代码生成（eBPF 仅支持 x86_64）"
    SKIP_EBPF="true"
fi

if [ -z "$SKIP_EBPF" ]; then
    # x86_64 架构：正常生成 eBPF 代码
    docker run --rm \
        --platform "${DOCKER_PLATFORM}" \
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
            GOARCH=${GO_ARCH} CGO_ENABLED=1 go build -buildvcs=false -o /workspace/build/agent/build/agent ./cmd/agent
        "
else
    # ARM64 架构：跳过 eBPF 生成，但仍需要 RDMA 开发库
    # 由于 rdmatracing_x86_bpfel.go 有 //go:build 386 || amd64 标签，在 ARM64 时不会被编译
    # 但 rdma_tracing.go 会编译并引用这些对象，导致编译错误
    # 解决方案：创建临时的 stub 文件来满足编译需求（不修改源码）
    # 注意：虽然跳过 eBPF 工具链，但仍需要安装 RDMA 开发库（libibverbs-dev, librdmacm-dev）
    # 因为 internal/rdma/device.go 使用了 CGO 并需要 infiniband/verbs.h 头文件
    echo "  跳过 eBPF 工具链安装，但仍安装 RDMA 开发库，创建临时 stub 文件以支持 ARM64 编译..."
    docker run --rm \
        --platform "${DOCKER_PLATFORM}" \
        -v "${PROJECT_ROOT}:/workspace" \
        -w /workspace/src/rpingmesh \
        golang:1.24-bullseye \
        sh -c "
            sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
            sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
            apt-get update && apt-get install -y --fix-missing \
                git ca-certificates \
                libibverbs-dev librdmacm-dev && \
            go mod download && \
            cd internal/ebpf && \
            # 创建临时的 ARM64 stub 文件（仅在构建时存在，不修改源码）
            cat > rdmatracing_arm64_stub.go << 'EOFSTUB'
//go:build arm64
// +build arm64

// 临时 stub 文件，用于 ARM64 架构编译时满足 rdma_tracing.go 的引用需求
// 此文件仅在构建时创建，不会提交到源码仓库
package ebpf

import \"github.com/cilium/ebpf\"

type rdmaTracingPrograms struct {
    TraceDestroyQpUser *ebpf.Program
    TraceModifyQp      *ebpf.Program
}

type rdmaTracingMaps struct {
    RdmaEvents *ebpf.Map
    RdmaStats  *ebpf.Map
}

type rdmaTracingVariables struct{}

type rdmaTracingObjects struct {
    rdmaTracingPrograms
    rdmaTracingMaps
    rdmaTracingVariables
}

func (o *rdmaTracingObjects) Close() error {
    return nil
}

func loadRdmaTracingObjects(obj interface{}, opts *ebpf.CollectionOptions) error {
    return nil
}
EOFSTUB
            cd /workspace/src/rpingmesh && \
            GOARCH=${GO_ARCH} CGO_ENABLED=1 go build -buildvcs=false -o /workspace/build/agent/build/agent ./cmd/agent && \
            # 构建完成后删除临时文件
            rm -f /workspace/src/rpingmesh/internal/ebpf/rdmatracing_arm64_stub.go
        "
fi

# 2. 构建Agent镜像

echo "2. 构建Agent镜像..."
cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}

docker buildx build \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    --build-arg GRPCURL_ARCH="${GRPCURL_ARCH}" \
    --load \
    -t "$IMAGE_NAME:$TAG" .

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


