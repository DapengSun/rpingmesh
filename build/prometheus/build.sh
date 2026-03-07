#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="rpingmesh-prometheus"
TAG="latest"

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

cd "${BUILD_DIR}"

echo "构建 Prometheus 镜像..."
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}
# 使用 buildx 进行跨架构构建，比 docker build 更稳定
# 传递 TARGETARCH 给 Dockerfile，用于根据架构选择合适的 apt 源
docker buildx build \
  --platform "${DOCKER_PLATFORM}" \
  --build-arg BUILD_UID="${BUILD_UID_ARG}" \
  --build-arg BUILD_GID="${BUILD_GID_ARG}" \
  --build-arg TARGETARCH="${TARGET_ARCH}" \
  --load \
  -t "${IMAGE_NAME}:${TAG}" .

echo "Built ${IMAGE_NAME}:${TAG}"
