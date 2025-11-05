#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-analyzer"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

GOPROXY_VAL="${GOPROXY:-https://goproxy.cn,direct}"

mkdir -p "$BUILD_DIR"
echo "1. 编译analyzer二进制..."

mkdir -p "$HOME/.cache/go-build" "$HOME/go/pkg/mod" || true

docker run --rm \
  -e GOPROXY="$GOPROXY_VAL" \
  -v "$REPO_ROOT:/workspace" \
  -v "$HOME/.cache/go-build:/root/.cache/go-build" \
  -v "$HOME/go/pkg/mod:/go/pkg/mod" \
  -w /workspace \
  golang:1.24-bullseye \
  sh -c 'set -e; \
    go env -w GOPROXY=$GOPROXY; \
    go env -w GOSUMDB=sum.golang.org; \
    go mod download -x; \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /workspace/analyzer-build/build/analyzer ./cmd/analyzer'

echo "2. 构建analyzer镜像..."
cd "$BUILD_DIR"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Analyzer镜像构建完成！"
docker images "$IMAGE_NAME:$TAG"
