#!/bin/bash
set -e

# Script 5: Verify server-side services (rqlite, controller and analyzer)
# Simple verification through supervisor logs and HTTP ports

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_container() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

check_http() {
    local url=$1
    if curl -sf "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_log() {
    local container=$1
    local pattern=$2
    if docker logs "$container" 2>&1 | grep -q "$pattern" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

echo "Verifying server-side services..."

# Check RQLite
echo ""
echo "RQLite:"
if check_container "rpingmesh-rqlite-server"; then
    print_ok "Container is running"
    
    if check_http "http://localhost:4001/status"; then
        ready=$(curl -sf http://localhost:4001/status 2>/dev/null | grep -o '"ready":true' || echo "")
        if [ -n "$ready" ]; then
            print_ok "HTTP endpoint is accessible (ready: true)"
        else
            print_fail "HTTP endpoint accessible but not ready"
        fi
    else
        print_fail "HTTP endpoint not accessible"
    fi
    
    if check_log "rpingmesh-rqlite-server" "rqlite entered RUNNING state"; then
        print_ok "Supervisor log shows RUNNING state"
    else
        print_fail "Supervisor log does not show RUNNING state"
    fi
else
    print_fail "Container is not running"
fi

# Check Controller
echo ""
echo "Controller:"
if check_container "rpingmesh-controller-server"; then
    print_ok "Container is running"
    
    if check_http "http://localhost:50051" 2>/dev/null || nc -zv localhost 50051 2>/dev/null; then
        print_ok "gRPC port 50051 is accessible"
    else
        print_fail "gRPC port 50051 not accessible"
    fi
    
    if check_log "Initializing RNIC registry with rqlite"; then
        print_ok "RNIC registry initialized"
    else
        print_fail "RNIC registry not initialized"
    fi
    
    if check_log "Starting gRPC server"; then
        print_ok "gRPC server started"
    else
        print_fail "gRPC server not started"
    fi
else
    print_fail "Container is not running"
fi

# Check Analyzer
echo ""
echo "Analyzer:"
if check_container "rpingmesh-analyzer-server"; then
    print_ok "Container is running"
    
    if check_http "http://localhost:50052" 2>/dev/null || nc -zv localhost 50052 2>/dev/null; then
        print_ok "gRPC port 50052 is accessible"
    else
        print_fail "gRPC port 50052 not accessible"
    fi
    
    if check_log "Initializing analyzer storage"; then
        print_ok "Analyzer storage initialized"
    else
        print_fail "Analyzer storage not initialized"
    fi
    
    if check_log "Starting gRPC server"; then
        print_ok "gRPC server started"
    else
        print_fail "gRPC server not started"
    fi
else
    print_fail "Container is not running"
fi

echo ""
echo "Verification complete"

