#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-agent-simulator"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

echo "构建 R-Pingmesh Agent Simulator 镜像..."
echo "构建目录: ${BUILD_DIR}"

docker run --rm \
    -v "${REPO_ROOT}:/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
        apt-get update && apt-get install -y --fix-missing git ca-certificates && \
        go mod download && \
        CGO_ENABLED=0 go build -o /workspace/simulator-build/build/simulator ./cmd/simulator
    "

cd "${BUILD_DIR}"
docker build -t "${IMAGE_NAME}:${TAG}" .

echo "Simulator 镜像构建完成！"
docker images "${IMAGE_NAME}:${TAG}"

