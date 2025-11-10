#!/bin/bash
set -euo pipefail

GRAFANA_BASE_PATH=${GRAFANA_BASE_PATH:-/private/rpingmesh/grafana}

mkdir -p "${GRAFANA_BASE_PATH}"
chown -R 472:472 "${GRAFANA_BASE_PATH}"

CONFIG_DIR="${GRAFANA_BASE_PATH}/config"
DATA_DIR="${GRAFANA_BASE_PATH}/data"
LOG_DIR="${GRAFANA_BASE_PATH}/logs"
PLUGINS_DIR="${GRAFANA_BASE_PATH}/plugins"
PROVISIONING_DIR="${GRAFANA_BASE_PATH}/provisioning"
PROVISIONING_DS_DIR="${PROVISIONING_DIR}/datasources"
PROVISIONING_DASH_DIR="${PROVISIONING_DIR}/dashboards"

CONFIG_SOURCE="/mnt/config-source/grafana.ini"
DATASOURCE_SOURCE="/mnt/config-source/datasources.yml"
DASHBOARDS_SOURCE="/mnt/config-source/dashboards.yml"
DEFAULT_DASHBOARD_SOURCE="/mnt/config-source/default_dashboard.json"

DEFAULT_CONFIG="/tmp/grafana.ini"
DEFAULT_DATASOURCE="/tmp/datasources.yml"
DEFAULT_DASHBOARDS="/tmp/dashboards.yml"
DEFAULT_DASHBOARD_JSON="/tmp/default_dashboard.json"
DEFAULT_DASHBOARD_DIR="/tmp/dashboards"

mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${PLUGINS_DIR}" \
         "${PROVISIONING_DS_DIR}" "${PROVISIONING_DASH_DIR}"

chown -R 472:472 "${GRAFANA_BASE_PATH}"

# 复制 grafana.ini（优先挂载目录，其次镜像内默认模板）
if [ -f "${CONFIG_SOURCE}" ]; then
    cp "${CONFIG_SOURCE}" "${CONFIG_DIR}/grafana.ini"
elif [ ! -f "${CONFIG_DIR}/grafana.ini" ] && [ -f "${DEFAULT_CONFIG}" ]; then
    cp "${DEFAULT_CONFIG}" "${CONFIG_DIR}/grafana.ini"
fi

# 复制 datasource 配置
if [ -f "${DATASOURCE_SOURCE}" ]; then
    cp "${DATASOURCE_SOURCE}" "${PROVISIONING_DS_DIR}/datasources.yml"
elif [ ! -f "${PROVISIONING_DS_DIR}/datasources.yml" ] && [ -f "${DEFAULT_DATASOURCE}" ]; then
    cp "${DEFAULT_DATASOURCE}" "${PROVISIONING_DS_DIR}/datasources.yml"
fi

# 复制 dashboard provider 配置
if [ -f "${DASHBOARDS_SOURCE}" ]; then
    cp "${DASHBOARDS_SOURCE}" "${PROVISIONING_DASH_DIR}/dashboards.yml"
elif [ ! -f "${PROVISIONING_DASH_DIR}/dashboards.yml" ] && [ -f "${DEFAULT_DASHBOARDS}" ]; then
    cp "${DEFAULT_DASHBOARDS}" "${PROVISIONING_DASH_DIR}/dashboards.yml"
fi

# 覆盖或初始化默认 dashboard
if [ -f "${DEFAULT_DASHBOARD_SOURCE}" ]; then
    cp "${DEFAULT_DASHBOARD_SOURCE}" "${PROVISIONING_DASH_DIR}/default_dashboard.json"
elif [ ! -f "${PROVISIONING_DASH_DIR}/default_dashboard.json" ] && [ -f "${DEFAULT_DASHBOARD_JSON}" ]; then
    cp "${DEFAULT_DASHBOARD_JSON}" "${PROVISIONING_DASH_DIR}/default_dashboard.json"
fi

# 复制镜像内其它预置 dashboard（仅在目标不存在时复制）
if [ -d "${DEFAULT_DASHBOARD_DIR}" ]; then
    for dashboard in "${DEFAULT_DASHBOARD_DIR}"/*.json; do
        [ -f "${dashboard}" ] || continue
        dashboard_name=$(basename "${dashboard}")
        target_path="${PROVISIONING_DASH_DIR}/${dashboard_name}"
        if [ ! -f "${target_path}" ]; then
            cp "${dashboard}" "${target_path}"
        fi
    done
fi

CONFIG_FILE="${CONFIG_DIR}/grafana.ini"

GRAFANA_CMD=(/usr/share/grafana/bin/grafana server --homepath=/usr/share/grafana --packaging=docker)
if [ -f "${CONFIG_FILE}" ]; then
    GRAFANA_CMD+=(--config="${CONFIG_FILE}")
fi

if command -v su-exec >/dev/null 2>&1; then
    exec su-exec grafana:grafana "${GRAFANA_CMD[@]}"
else
    exec su -s /bin/sh grafana -c "${GRAFANA_CMD[*]}"
fi
