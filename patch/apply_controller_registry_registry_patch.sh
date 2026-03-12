#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${REPO_ROOT}/src/rpingmesh"
TARGET_FILE="${SUBMODULE_DIR}/internal/controller/registry/registry.go"
PATCH_FILE="${SCRIPT_DIR}/internal/controller/registry/registry.go"

mkdir -p "$(dirname "${TARGET_FILE}")"
cp "${PATCH_FILE}" "${TARGET_FILE}"

echo "已更新 ${TARGET_FILE}"

