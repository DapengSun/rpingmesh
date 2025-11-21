#!/bin/bash
set -e

# Script 3: Initialize persistent directory structure for server-side components
# This script creates the directory structure for persistent storage under the parent directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Load environment variables from .env if exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Get data directory from environment or use default
DATA_DIR="${RPINGMESH_DATA_DIR:-./data_dir}"

# Resolve to absolute path if relative
if [[ "$DATA_DIR" != /* ]]; then
    DATA_DIR="$(cd "$SCRIPT_DIR" && cd "$(dirname "$DATA_DIR")" && pwd)/$(basename "$DATA_DIR")"
fi

print_info "Initializing persistent directories for server-side components under: $DATA_DIR/rpingmesh"

# Default UID and GID (matching Dockerfile BUILD_UID and BUILD_GID)
BUILD_UID=${BUILD_UID:-2133}
BUILD_GID=${BUILD_GID:-2015}

# Create directories with rpingmesh hierarchy (only server-side components)
mkdir -p "$DATA_DIR/rpingmesh/controller"
mkdir -p "$DATA_DIR/rpingmesh/analyzer"
mkdir -p "$DATA_DIR/rpingmesh/rqlite"
mkdir -p "$DATA_DIR/rpingmesh/otel-collector"
mkdir -p "$DATA_DIR/rpingmesh/prometheus"
mkdir -p "$DATA_DIR/rpingmesh/grafana"

# Set ownership for directories (especially important for grafana and prometheus)
# Note: chown may fail if running as non-root, but that's okay - container will fix it
chown -R "${BUILD_UID}:${BUILD_GID}" "$DATA_DIR/rpingmesh/grafana" 2>/dev/null || true
chown -R "${BUILD_UID}:${BUILD_GID}" "$DATA_DIR/rpingmesh/prometheus" 2>/dev/null || true

print_info "Directory initialization complete"

