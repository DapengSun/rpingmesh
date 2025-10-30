#!/bin/bash
set -e

IMAGE_NAME="rpingmesh-analyzer"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"

# 允许外部自定义 GOPROXY，默认使用国内镜像
GOPROXY_VAL="${GOPROXY:-https://goproxy.cn,direct}"

mkdir -p "$BUILD_DIR"
echo "1. 编译analyzer二进制..."

# 复用宿主机 Go 构建缓存与模块缓存以加速
mkdir -p "$HOME/.cache/go-build" "$HOME/go/pkg/mod" || true

docker run --rm \
  -e GOPROXY="$GOPROXY_VAL" \
  -v "$REPO_ROOT:/workspace" \
  -v "$HOME/.cache/go-build:/root/.cache/go-build" \
  -v "$HOME/go/pkg/mod:/go/pkg/mod" \
  -w /workspace \
  golang:1.24-bullseye \
  sh -c 'set -e; \
    echo "GOPROXY=$GOPROXY"; \
    go env -w GOPROXY=$GOPROXY; \
    go env -w GOSUMDB=sum.golang.org; \
    go mod download -x; \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /workspace/analyzer-build/build/analyzer ./cmd/analyzer'

echo "2. 构建analyzer镜像..."
cd "$BUILD_DIR"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Analyzer镜像构建完成！"
echo
echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"

echo
echo "=== Analyzer使用方法 ==="
echo
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > analyzer.tar.gz"

echo
echo "2. 在目标平台加载:"
echo "   docker load < analyzer.tar.gz"

echo
echo "3. 启动Analyzer (环境变量驱动):"
echo "   docker run -d \\" \
     " --name analyzer \\" \
     " --network rpingmesh-network \\" \
     " -e LISTEN_ADDR=0.0.0.0:50052 \\" \
     " -e DATABASE_URI=http://rqlite:4001 \\" \
     " -p 50052:50052 \\" \
     " -p 2224:22 \\" \
     " $IMAGE_NAME:$TAG"

echo
echo "4. 查看日志:"
echo "   docker exec -it analyzer bash"
echo "   tail -f /var/log/supervisor/analyzer.log"
