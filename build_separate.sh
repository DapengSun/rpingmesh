#!/bin/bash

# 分离式构建脚本 - 构建Controller和Agent独立镜像
set -e

echo "开始构建R-Pingmesh镜像..."

# 1. 构建Controller镜像
echo "1. 构建Controller镜像..."
./build_controller.sh

echo
echo "=" * 50
echo

# 2. 构建Agent镜像
echo "2. 构建Agent镜像..."
./build_agent.sh

echo
echo "=" * 50
echo

# 3. 显示所有镜像
echo "所有构建的镜像:"
docker images | grep rpingmesh

echo
echo "分离式构建完成！"