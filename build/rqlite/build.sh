#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-rqlite"
TAG="latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

echo "构建 RQLite 镜像..."
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}

docker buildx build \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    --build-arg RQLITE_VERSION="8.37.0" \
    --build-arg RQLITE_ARCH="${RQLITE_ARCH}" \
    --load \
    -t "$IMAGE_NAME:$TAG" .

echo "RQLite镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
