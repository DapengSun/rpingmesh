#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-agent-simulator"
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

echo "构建 R-Pingmesh Agent Simulator 镜像..."
echo "构建目录: ${BUILD_DIR}"

docker run --rm \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace/src/rpingmesh \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        apt-get update && apt-get install -y --fix-missing git ca-certificates && \
        go mod download && \
        CGO_ENABLED=0 go build -o /workspace/build/simulator/build/simulator ./cmd/simulator
    "

cd "${BUILD_DIR}"
docker build -t "${IMAGE_NAME}:${TAG}" .

echo "Simulator 镜像构建完成！"
docker images "${IMAGE_NAME}:${TAG}"

