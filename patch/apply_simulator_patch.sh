#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${REPO_ROOT}/src/rpingmesh"
TARGET_DIR="${SUBMODULE_DIR}/cmd/simulator"
PATCH_DIR="${SCRIPT_DIR}/simulator"

if [ ! -d "${PATCH_DIR}" ]; then
    echo "未找到补丁目录: ${PATCH_DIR}"
    exit 1
fi

if [ ! -e "${SUBMODULE_DIR}/go.mod" ]; then
    echo "未检测到 src/rpingmesh 子模块内容，请先执行:"
    echo "  git submodule update --init --recursive"
    exit 1
fi

mkdir -p "${TARGET_DIR}"

cp -r "${PATCH_DIR}/." "${TARGET_DIR}/"

echo "已将补丁内容复制到: ${TARGET_DIR}"

