#!/bin/bash
set -e

CONFIG_DIR="/app/config"
CONFIG_SOURCE="/mnt/config-source/simulator.yaml"
PERSIST_BASE="/private/rpingmesh/simulator"
PERSIST_CONFIG_DIR="${PERSIST_BASE}/config"
PERSIST_DATA_DIR="${PERSIST_BASE}/data"
PERSIST_FILE="${PERSIST_CONFIG_DIR}/simulator.yaml"

BUILD_USER=${BUILD_USER:-rpingmesh}
BUILD_GROUP=${BUILD_GROUP:-rpingmesh}
BUILD_UID=${BUILD_UID:-2133}
BUILD_GID=${BUILD_GID:-2015}

mkdir -p "${PERSIST_CONFIG_DIR}" "${PERSIST_DATA_DIR}"
chown -R "${BUILD_UID}:${BUILD_GID}" "${PERSIST_BASE}" || true

if [ -f "${CONFIG_SOURCE}" ] && [ -s "${CONFIG_SOURCE}" ]; then
    if [ ! -f "${PERSIST_FILE}" ]; then
        echo "信息: 检测到配置源 ${CONFIG_SOURCE}，首次复制到持久化路径 ${PERSIST_FILE}"
        cp "${CONFIG_SOURCE}" "${PERSIST_FILE}"
    else
        echo "信息: 持久化配置已存在 ${PERSIST_FILE}，跳过覆盖"
        if [ ! -s "${PERSIST_FILE}" ]; then
            echo "警告: 持久化配置文件存在但为空: ${PERSIST_FILE}" >&2
        fi
    fi
elif [ -f "${PERSIST_FILE}" ]; then
    if [ -s "${PERSIST_FILE}" ]; then
        echo "信息: 使用持久化目录中的配置文件: ${PERSIST_FILE}"
    else
        echo "警告: 持久化配置文件存在但为空: ${PERSIST_FILE}" >&2
    fi
fi

if [ ! -f "${PERSIST_FILE}" ] || [ ! -s "${PERSIST_FILE}" ]; then
    echo "错误: 未找到有效的配置文件。请确保以下任一路径存在非空文件:" >&2
    echo "  - 持久化路径: ${PERSIST_FILE}" >&2
    echo "  - 配置源路径: ${CONFIG_SOURCE}" >&2
    exit 1
fi

if [ -L "${CONFIG_DIR}" ] || [ -e "${CONFIG_DIR}" ]; then
    rm -rf "${CONFIG_DIR}"
fi
ln -sf "${PERSIST_CONFIG_DIR}" "${CONFIG_DIR}"
chown -R "${BUILD_UID}:${BUILD_GID}" "${PERSIST_CONFIG_DIR}" "${PERSIST_DATA_DIR}" || true

CONFIG_SIM_FILE="${CONFIG_DIR}/simulator.yaml"

# 如果配置中禁用了模拟器，则保持容器存活但不启动模拟器进程
if grep -qiE '^\s*enabled\s*:\s*false' "${CONFIG_SIM_FILE}"; then
    echo "信息: 配置中 simulation.enabled=false，保持容器空闲运行"
    if command -v runuser >/dev/null 2>&1; then
        exec runuser -u "${BUILD_USER}" -- tail -f /dev/null
    else
        exec su -s /bin/sh "${BUILD_USER}" -c "tail -f /dev/null"
    fi
fi

SIM_CMD=(/usr/local/bin/simulator --config "${CONFIG_SIM_FILE}")
if [ -n "${SIMULATION_WORKER:-}" ]; then
    SIM_CMD+=("--worker" "${SIMULATION_WORKER}")
    echo "信息: 使用模拟器 worker ${SIMULATION_WORKER}"
fi

if command -v runuser >/dev/null 2>&1; then
    exec runuser -u "${BUILD_USER}" -- "${SIM_CMD[@]}"
else
    cmd_string=""
    for arg in "${SIM_CMD[@]}"; do
        cmd_string="${cmd_string}$(printf '%q ' "${arg}")"
    done
    exec su -s /bin/sh "${BUILD_USER}" -c "${cmd_string}"
fi


