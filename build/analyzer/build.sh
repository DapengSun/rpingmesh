#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-analyzer"
TAG="latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
BUILD_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${BUILD_ROOT}/.." && pwd)"
SRC_ROOT="${PROJECT_ROOT}/src/rpingmesh"

# 加载架构配置
source "${BUILD_ROOT}/build-common.sh"

GOPROXY_VAL="${GOPROXY:-https://goproxy.cn,direct}"

if [ ! -d "${SRC_ROOT}" ]; then
  echo "未找到源码目录: ${SRC_ROOT}"
  exit 1
fi

mkdir -p "$BUILD_DIR"
echo "1. 编译analyzer二进制..."
echo "目标架构: ${TARGET_ARCH} (${DOCKER_PLATFORM})"

mkdir -p "$HOME/.cache/go-build" "$HOME/go/pkg/mod" || true

docker run --rm \
  --platform "${DOCKER_PLATFORM}" \
  -e GOPROXY="$GOPROXY_VAL" \
  -v "$PROJECT_ROOT:/workspace" \
  -v "$HOME/.cache/go-build:/root/.cache/go-build" \
  -v "$HOME/go/pkg/mod:/go/pkg/mod" \
  -w /workspace/src/rpingmesh \
  golang:1.24-bullseye \
  sh -c "set -e; \
    go env -w GOPROXY=\$GOPROXY; \
    go env -w GOSUMDB=sum.golang.org; \
    go mod download -x; \
    GOARCH=${GO_ARCH} CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags \"-s -w\" -o /workspace/build/analyzer/build/analyzer ./cmd/analyzer"

echo "2. 构建analyzer镜像..."
cd "$BUILD_DIR"
BUILD_UID_ARG=${BUILD_UID:-2133}
BUILD_GID_ARG=${BUILD_GID:-2015}

docker buildx build \
  --platform "${DOCKER_PLATFORM}" \
  --build-arg BUILD_UID="${BUILD_UID_ARG}" \
  --build-arg BUILD_GID="${BUILD_GID_ARG}" \
  --load \
  -t "$IMAGE_NAME:$TAG" .

echo "Analyzer镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
