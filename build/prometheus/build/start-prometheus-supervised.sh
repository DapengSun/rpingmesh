#!/bin/bash
set -euo pipefail

BUILD_USER=${BUILD_USER:-rpingmesh}
BUILD_GROUP=${BUILD_GROUP:-rpingmesh}
BUILD_UID=${BUILD_UID:-2133}
BUILD_GID=${BUILD_GID:-2015}

PROMETHEUS_BASE_PATH=${PROMETHEUS_BASE_PATH:-/private/rpingmesh/prometheus}
CONFIG_DIR="${PROMETHEUS_BASE_PATH}/config"
DATA_DIR="${PROMETHEUS_BASE_PATH}/data"
RULES_DIR="${PROMETHEUS_BASE_PATH}/rules"
TARGETS_DIR="${PROMETHEUS_BASE_PATH}/targets"
CONFIG_FILE="${CONFIG_DIR}/prometheus.yml"
CONFIG_SOURCE="/mnt/config-source/prometheus.yml"
TEMPLATE_FILE="/etc/prometheus/prometheus.yml"

mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${RULES_DIR}" "${TARGETS_DIR}"
chown -R "${BUILD_UID}:${BUILD_GID}" "${PROMETHEUS_BASE_PATH}" || true

if [ -f "${CONFIG_SOURCE}" ] && [ -s "${CONFIG_SOURCE}" ]; then
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "[INFO] 发现挂载的配置模板，复制到持久化目录: ${CONFIG_SOURCE} -> ${CONFIG_FILE}"
        cp "${CONFIG_SOURCE}" "${CONFIG_FILE}"
    else
        echo "[INFO] 使用已有的持久化配置文件: ${CONFIG_FILE}"
    fi
else
    if [ ! -f "${CONFIG_FILE}" ]; then
        if [ ! -f "${TEMPLATE_FILE}" ]; then
            echo "[ERROR] 模板文件 ${TEMPLATE_FILE} 不存在，无法生成 prometheus.yml" >&2
            exit 1
        fi
        echo "[INFO] 生成默认 prometheus.yml 到持久化目录"
        sed "s|\${PROMETHEUS_BASE_PATH}|${PROMETHEUS_BASE_PATH}|g" "${TEMPLATE_FILE}" > "${CONFIG_FILE}"
    fi
fi

export PROMETHEUS_BASE_PATH

echo "[INFO] Prometheus base path: ${PROMETHEUS_BASE_PATH}"
echo "[INFO] Config file: ${CONFIG_FILE}"
echo "[INFO] Data dir: ${DATA_DIR}"

PROMETHEUS_CMD=(
    /bin/prometheus
    --config.file="${CONFIG_FILE}"
    --storage.tsdb.path="${DATA_DIR}"
    --web.enable-lifecycle
    --web.console.libraries=/usr/share/prometheus/console_libraries
    --web.console.templates=/usr/share/prometheus/consoles
)

if command -v runuser >/dev/null 2>&1; then
    exec runuser -u "${BUILD_USER}" -- "${PROMETHEUS_CMD[@]}"
else
    cmd_string=""
    for arg in "${PROMETHEUS_CMD[@]}"; do
        cmd_string="${cmd_string}$(printf '%q ' "${arg}")"
    done
    exec su -s /bin/sh "${BUILD_USER}" -c "${cmd_string}"
fi
