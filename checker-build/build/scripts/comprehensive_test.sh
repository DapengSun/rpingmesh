#!/bin/bash
set -e

echo "=========================================="
echo "    R-Pingmesh 环境综合检测"
echo "=========================================="
echo "检测时间: $(date)"
echo "主机名: $(hostname)"
echo "内核版本: $(uname -r)"
echo

run_step() {
  local title="$1"; shift
  echo
  echo "[STEP] $title"
  echo "----------------------------------------"
  "$@" || echo "(忽略错误) $*"
}

# 1. RDMA 环境
[ -x /app/scripts/check_rdma_support.sh ] && run_step "RDMA 环境" /app/scripts/check_rdma_support.sh

# 2. 兼容性
[ -x /app/scripts/check_rpingmesh_compatibility.sh ] && run_step "R-Pingmesh 兼容性" /app/scripts/check_rpingmesh_compatibility.sh

# 3. 快速 RDMA 功能测试
[ -x /app/scripts/quick_rdma_test.sh ] && run_step "快速 RDMA 功能测试" /app/scripts/quick_rdma_test.sh

# 4. 增强 RDMA 测试（可选，可能较慢）
[ -x /app/scripts/enhanced_rdma_test.sh ] && run_step "增强 RDMA 测试" /app/scripts/enhanced_rdma_test.sh

echo
echo "=========================================="
echo "           检测完成"
echo "=========================================="
