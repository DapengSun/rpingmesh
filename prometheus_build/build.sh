#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build"
IMAGE_NAME="rpingmesh-prometheus"
TAG="latest"

cd "${BUILD_DIR}"

docker build -t "${IMAGE_NAME}:${TAG}" .

echo "Built ${IMAGE_NAME}:${TAG}"
