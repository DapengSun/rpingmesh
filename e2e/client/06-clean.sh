#!/bin/bash
set -e

# Script 6: Clean up client-side agent containers and persistent data directories
# Stops containers and clears persistent directories

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
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

print_info "Stopping containers..."
docker compose down

print_info "Clearing persistent data directories..."

if [ -d "$DATA_DIR" ]; then
    agent_dir="$DATA_DIR/rpingmesh/agent"
    if [ -d "$agent_dir" ]; then
        print_info "Clearing $agent_dir..."
        rm -rf "$agent_dir"/*
        print_info "  ✓ Cleared agent"
    fi
    print_info "All persistent data cleared"
else
    print_warn "Data directory not found: $DATA_DIR"
fi

print_info "Cleanup complete"

