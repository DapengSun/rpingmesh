#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-agent-simulator"
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

echo "构建 R-Pingmesh Agent Simulator 镜像..."
echo "构建目录: ${BUILD_DIR}"
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

# 注意：Go 支持交叉编译，但仍需要指定 --platform 以确保使用正确的架构镜像
# 这样可以避免平台不匹配的警告
docker run --rm \
    --platform "${DOCKER_PLATFORM}" \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace/src/rpingmesh \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        apt-get update && apt-get install -y --fix-missing git ca-certificates && \
        go mod download && \
        GOARCH=${GO_ARCH} CGO_ENABLED=0 go build -o /workspace/build/simulator/build/simulator ./cmd/simulator
    "

cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}
# 使用 buildx 进行跨架构构建，比 docker build 更稳定
docker buildx build \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    --load \
    -t "${IMAGE_NAME}:${TAG}" .

echo "Simulator 镜像构建完成！"
docker images "${IMAGE_NAME}:${TAG}"

