#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="rpingmesh-grafana"
TAG="latest"

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

cd "${BUILD_DIR}"

echo "构建 Grafana 镜像..."
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}

docker buildx build \
  --platform "${DOCKER_PLATFORM}" \
  --build-arg BUILD_UID="${BUILD_UID_ARG}" \
  --build-arg BUILD_GID="${BUILD_GID_ARG}" \
  --load \
  -t "${IMAGE_NAME}:${TAG}" .

echo "Built ${IMAGE_NAME}:${TAG}"
