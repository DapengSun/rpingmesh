#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-controller"
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

echo "构建 Controller 镜像..."

echo "1. 构建Controller二进制文件..."
docker run --rm \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace/src/rpingmesh \
    golang:1.24-bullseye \
    sh -c "
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates &&
        go mod download &&
        go build -o /workspace/build/controller/build/controller ./cmd/controller
    "

echo "2. 构建Controller镜像..."
cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}
docker build \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    -t "$IMAGE_NAME:$TAG" .

echo "Controller镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
