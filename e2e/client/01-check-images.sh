#!/bin/bash
set -e

# Script 1: Check if all required Docker images for client-side agent are available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

print_info "Checking required Docker images for client-side agent..."

missing_images=0
required_images=(
    "rpingmesh-agent:latest"
)

for image in "${required_images[@]}"; do
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        print_error "Missing required image: $image"
        missing_images=$((missing_images + 1))
    else
        print_info "✓ Found: $image"
    fi
done

if [ $missing_images -gt 0 ]; then
    print_error ""
    print_error "Missing $missing_images required image(s)"
    print_info ""
    print_info "Please import or build images first:"
    print_info "  To import from tar files:"
    print_info "    docker load < agent.tar.gz"
    print_info ""
    print_info "  To build from source:"
    print_info "    cd ../../agent-build && bash build.sh"
    exit 1
fi

print_info ""
print_info "All required images are available ✓"
exit 0

