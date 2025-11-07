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

check_startup_health() {
    local container=$1
    local name=$2
    local wait_seconds=${3:-5}

    echo "Waiting ${wait_seconds}s for ${name} startup logs..."
    sleep "$wait_seconds"

    local since_ts
    since_ts=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null || true)
    if [ -z "$since_ts" ] || [ "$since_ts" = "<no value>" ]; then
        since_ts=$(date -Iseconds)
    fi

    local recent_logs
    recent_logs=$(docker logs "$container" --since "$since_ts" 2>&1 || true)

    if [ -z "$recent_logs" ]; then
        print_fail "${name} startup logs unavailable"
        return
    fi

    if echo "$recent_logs" | grep -Ei 'exit status [1-9]|entered FATAL state|level"?:"?fatal|panic|failed to ' >/dev/null 2>&1; then
        print_fail "${name} startup logs contain errors"
        echo "---- Recent ${name} logs ----"
        echo "$recent_logs"
        echo "-----------------------------"
    else
        print_ok "${name} startup logs look healthy"
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
    
    if check_log "rqlite entered RUNNING state"; then
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
    
    check_startup_health "rpingmesh-controller-server" "Controller"
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
    
    check_startup_health "rpingmesh-analyzer-server" "Analyzer"
else
    print_fail "Container is not running"
fi

# Check Prometheus
echo ""
echo "Prometheus:"
if check_container "rpingmesh-prometheus-server"; then
    print_ok "Container is running"

    if check_http "http://localhost:9091/-/ready"; then
        print_ok "HTTP readiness endpoint is accessible"
    else
        if nc -zv localhost 9091 >/dev/null 2>&1; then
            print_fail "Ready endpoint not responding, but port 9091 is reachable"
        else
            print_fail "Prometheus port 9091 not accessible"
        fi
    fi

    check_startup_health "rpingmesh-prometheus-server" "Prometheus" 10
else
    print_fail "Container is not running"
fi

# Check Grafana
echo ""
echo "Grafana:"
if check_container "rpingmesh-grafana-server"; then
    print_ok "Container is running"

    if check_http "http://localhost:3000/login"; then
        print_ok "Login page reachable"
    else
        if nc -zv localhost 3000 >/dev/null 2>&1; then
            print_fail "Grafana port 3000 reachable but HTTP check failed"
        else
            print_fail "Grafana port 3000 not accessible"
        fi
    fi

    check_startup_health "rpingmesh-grafana-server" "Grafana" 15
else
    print_fail "Container is not running"
fi

echo ""
echo "Verification complete"

