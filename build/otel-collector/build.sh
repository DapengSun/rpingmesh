#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-otel-collector"
TAG="latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

echo "构建 OpenTelemetry Collector 镜像..."
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}

docker buildx build \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg BUILD_UID="${BUILD_UID_ARG}" \
    --build-arg BUILD_GID="${BUILD_GID_ARG}" \
    --build-arg OTELCOL_VERSION="0.139.0" \
    --build-arg OTELCOL_ARCH="${OTELCOL_ARCH}" \
    --load \
    -t "$IMAGE_NAME:$TAG" .

echo "OpenTelemetry Collector镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"

