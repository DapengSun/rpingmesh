#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${REPO_ROOT}/src/rpingmesh"
TARGET_FILE="${SUBMODULE_DIR}/internal/agent/telemetry/otel_metrics.go"
PATCH_FILE="${SCRIPT_DIR}/internal/agent/telemetry/otel_metrics.go"

if [ ! -e "${SUBMODULE_DIR}/go.mod" ]; then
    echo "未检测到 src/rpingmesh 子模块内容，请先执行:"
    echo "  git submodule update --init --recursive"
    exit 1
fi

if [ ! -f "${PATCH_FILE}" ]; then
    echo "未找到补丁文件: ${PATCH_FILE}"
    exit 1
fi

mkdir -p "$(dirname "${TARGET_FILE}")"
cp "${PATCH_FILE}" "${TARGET_FILE}"

echo "已更新 ${TARGET_FILE}"
