#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-rqlite"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

echo "构建 RQLite 镜像..."

cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "RQLite镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
