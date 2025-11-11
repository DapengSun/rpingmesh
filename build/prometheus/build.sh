#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"
IMAGE_NAME="rpingmesh-prometheus"
TAG="latest"

cd "${BUILD_DIR}"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}
docker build \
  --build-arg BUILD_UID="${BUILD_UID_ARG}" \
  --build-arg BUILD_GID="${BUILD_GID_ARG}" \
  -t "${IMAGE_NAME}:${TAG}" .

echo "Built ${IMAGE_NAME}:${TAG}"
