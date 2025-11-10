#!/bin/bash

# Checker 独立构建脚本（对齐 controller-build 结构）
set -e

IMAGE_NAME="rpingmesh-checker"
TAG="latest"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build"

echo "构建 R-Pingmesh Checker 镜像..."
echo "构建目录: ${BUILD_DIR}"

# 1. 构建Checker镜像
echo "1. 构建Checker镜像..."
cd "${BUILD_DIR}"
docker build -t "$IMAGE_NAME:$TAG" .

echo "Checker镜像构建完成！"
echo

echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"

echo

cat <<EOF
=== Checker使用方法 ===

1. 保存镜像:
   docker save $IMAGE_NAME:$TAG | gzip > checker.tar.gz

2. 在目标平台加载:
   docker load < checker.tar.gz

3. 启动Checker容器:
   docker run -d \
     --name checker \
     --privileged \
     --network host \
     -v $(pwd)/checker-data:/data \
     $IMAGE_NAME:$TAG

4. 在容器内运行检测:
   docker exec -it checker /app/scripts/quick_check.sh
   docker exec -it checker /app/scripts/comprehensive_test.sh
   docker exec -it checker /bin/bash
EOF
