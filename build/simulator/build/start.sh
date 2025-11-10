#!/bin/bash
set -e

CONFIG_DIR="/app/config"
CONFIG_FILE="${CONFIG_DIR}/simulator.yaml"
CONFIG_SOURCE="/mnt/config-source/simulator.yaml"

mkdir -p "${CONFIG_DIR}"

if [ -f "${CONFIG_SOURCE}" ] && [ ! -f "${CONFIG_FILE}" ]; then
    cp "${CONFIG_SOURCE}" "${CONFIG_FILE}"
fi

if [ ! -f "${CONFIG_FILE}" ]; then
    cat <<'EOF' > "${CONFIG_FILE}"
simulation:
  enabled: false
  profile: tor-mesh
  otel-addr: grpc://otel-collector:4317
  agent-id: sim-agent
EOF
fi

exec /usr/local/bin/simulator --config "${CONFIG_FILE}"

