#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-controller"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

echo "构建 Controller 镜像..."

echo "1. 构建Controller二进制文件..."
docker run --rm \
    -v "${REPO_ROOT}:/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates &&
        go mod download &&
        go build -o /workspace/controller-build/build/controller ./cmd/controller
    "

echo "2. 构建Controller镜像..."
cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Controller镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
