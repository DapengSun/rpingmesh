#!/bin/bash
set -e

# Run E2E deployment script for server-side components
# This script executes steps 01-05 sequentially

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "Starting E2E deployment for server-side components..."
echo ""

# Step 01: Check images
print_info "Step 01: Checking Docker images..."
bash "$SCRIPT_DIR/01-check-images.sh"
echo ""

# Step 02: Set environment
print_info "Step 02: Setting environment variables..."
bash "$SCRIPT_DIR/02-set-env.sh"
echo ""

# Step 03: Initialize directories
print_info "Step 03: Initializing directories..."
bash "$SCRIPT_DIR/03-init-dirs.sh"
echo ""

# Step 04: Start docker-compose
print_info "Step 04: Starting docker-compose..."
bash "$SCRIPT_DIR/04-start-compose.sh"
echo ""

# Step 05: Verify services
print_info "Step 05: Verifying services..."
bash "$SCRIPT_DIR/05-verify.sh"
echo ""

print_info "E2E deployment completed successfully!"


