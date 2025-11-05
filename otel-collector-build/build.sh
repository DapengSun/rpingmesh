#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-otel-collector"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

echo "构建 OpenTelemetry Collector 镜像..."

cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "OpenTelemetry Collector镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"

