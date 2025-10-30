#!/bin/bash

# 分离式构建脚本 - 构建Checker、Agent、Controller、RQLite独立镜像
set -e

BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "开始构建R-Pingmesh镜像..."

# 1. 构建Checker镜像

echo "1. 构建Checker镜像..."
bash "$BUILD_ROOT"/checker-build/build.sh

echo

echo "=================================================="

echo

# 2. 构建Agent镜像

echo "2. 构建Agent镜像..."
bash "$BUILD_ROOT"/agent-build/build.sh

echo

echo "=================================================="

echo

# 3. 构建Controller镜像

echo "3. 构建Controller镜像..."
bash "$BUILD_ROOT"/controller-build/build.sh

echo

echo "=================================================="

echo

# 4. 构建RQLite镜像

echo "4. 构建RQLite镜像..."
bash "$BUILD_ROOT"/rqlite-build/build.sh

echo

echo "=================================================="

echo

# 5. 显示所有镜像

echo "所有构建的镜像:"

docker images | grep rpingmesh || true

echo

echo "分离式构建完成！"