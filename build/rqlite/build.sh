#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-rqlite"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

echo "构建 RQLite 镜像..."

cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}
docker build \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    -t "$IMAGE_NAME:$TAG" .

echo "RQLite镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
