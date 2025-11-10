#!/bin/bash
set -e

# Script 3: Initialize persistent directory structure for client-side agent
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

print_info "Initializing persistent directories for client-side agent under: $DATA_DIR/rpingmesh/agent"

# Create directories with rpingmesh hierarchy (agent + simulator components)
mkdir -p "$DATA_DIR/rpingmesh/agent"
mkdir -p "$DATA_DIR/rpingmesh/agent/config"
mkdir -p "$DATA_DIR/rpingmesh/agent/data"

mkdir -p "$DATA_DIR/rpingmesh/simulator"
mkdir -p "$DATA_DIR/rpingmesh/simulator/config"
mkdir -p "$DATA_DIR/rpingmesh/simulator/data"

print_info "Directory initialization complete"

