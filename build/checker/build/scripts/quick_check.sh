#!/bin/bash
set -e

echo "=== 快速环境检测 ==="

# RDMA 基础检查
if [ -x /app/scripts/check_rdma_support.sh ]; then
  /app/scripts/check_rdma_support.sh || true
else
  echo "缺少 /app/scripts/check_rdma_support.sh"
fi

echo
# 兼容性概要
if [ -x /app/scripts/check_rpingmesh_compatibility.sh ]; then
  /app/scripts/check_rpingmesh_compatibility.sh || true
else
  echo "缺少 /app/scripts/check_rpingmesh_compatibility.sh"
fi

echo "=== 快速检测完成 ==="
