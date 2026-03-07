#!/bin/bash
set -e

# Script 2: Set environment variables for persistent storage
# This script creates .env file with persistent directory configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Default persistent directory (relative to script directory)
DEFAULT_DATA_DIR="./data_dir"

# Allow override via command line argument or environment variable
DATA_DIR="${1:-${RPINGMESH_DATA_DIR:-$DEFAULT_DATA_DIR}}"

# Resolve to absolute path if relative
if [[ "$DATA_DIR" != /* ]]; then
    DATA_DIR="$(cd "$SCRIPT_DIR" && cd "$(dirname "$DATA_DIR")" && pwd)/$(basename "$DATA_DIR")"
fi

# Create .env file
ENV_FILE="$SCRIPT_DIR/.env"

cat > "$ENV_FILE" << EOF

RPINGMESH_DATA_DIR=$DATA_DIR

EOF

print_info "Environment variables configured in .env file"
print_info "  RPINGMESH_DATA_DIR=$DATA_DIR"

