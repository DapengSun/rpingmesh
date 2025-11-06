#!/bin/bash
set -e

# Script 4: Read environment variables and start docker-compose for server-side components
# This script loads environment from .env and starts docker-compose with proper volume mounts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment variables from .env if exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    print_info "Loading environment from .env file..."
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    print_warn ".env file not found. Using default values."
    print_info "Run ./02-set-env.sh first to configure persistent directory."
fi

# Get data directory from environment or use default
DATA_DIR="${RPINGMESH_DATA_DIR:-./data_dir}"

# Resolve to absolute path if relative
if [[ "$DATA_DIR" != /* ]]; then
    DATA_DIR="$(cd "$SCRIPT_DIR" && cd "$(dirname "$DATA_DIR")" && pwd)/$(basename "$DATA_DIR")"
fi

# Verify data directory exists
if [ ! -d "$DATA_DIR" ]; then
    print_error "Data directory does not exist: $DATA_DIR"
    print_info "Run ./03-init-dirs.sh first to initialize directory structure."
    exit 1
fi

# Verify component directories exist (under rpingmesh subdirectory)
MISSING_DIRS=()
for component in "controller" "rqlite" "analyzer" "otel-collector"; do
    if [ ! -d "$DATA_DIR/rpingmesh/$component" ]; then
        MISSING_DIRS+=("$component")
    fi
done

if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
    print_error "Missing component directories: ${MISSING_DIRS[*]}"
    print_info "Run ./03-init-dirs.sh first to initialize directory structure."
    exit 1
fi

# Export environment variables for docker-compose
export RPINGMESH_DATA_DIR="$DATA_DIR"

# Check if docker-compose.yml exists
if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

# Start docker-compose
print_info ""
print_info "Executing: docker compose up -d"
print_info ""

docker compose up -d

if [ $? -eq 0 ]; then
    print_info ""
    print_info "✓ Docker Compose started successfully"
    print_info ""
    print_info "Service status:"
    docker compose ps
    
    print_info ""
    print_info "View logs with:"
    print_info "  docker compose logs -f"
    print_info "  docker compose logs -f <service_name>"
    print_info ""
    print_info "Stop services with:"
    print_info "  docker compose down"
    print_info ""
    print_info "Note: Server-side services are exposed on host ports for client access:"
    print_info "  - Controller: localhost:50051"
    print_info "  - Analyzer: localhost:50052"
    print_info "  - RQLite: localhost:4001"
else
    print_error "Failed to start docker-compose"
    exit 1
fi

