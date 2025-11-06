#!/bin/bash
set -e

# Script 5: Verify client-side agent service
# Simple verification through supervisor logs

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

check_log() {
    local container=$1
    local pattern=$2
    if docker logs "$container" 2>&1 | grep -q "$pattern" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

echo "Verifying client-side agent service..."

# Check Agent
echo ""
echo "Agent:"
if check_container "rpingmesh-agent-client"; then
    print_ok "Container is running"
    
    # Check supervisor is running
    if check_log "rpingmesh-agent-client" "supervisord"; then
        print_ok "Supervisor is running"
    else
        print_fail "Supervisor may not be running"
    fi
    
    # Check if agent process is registered in supervisor
    if docker exec rpingmesh-agent-client supervisorctl status agent >/dev/null 2>&1; then
        agent_status=$(docker exec rpingmesh-agent-client supervisorctl status agent 2>/dev/null | awk '{print $2}')
        if [ "$agent_status" = "RUNNING" ]; then
            print_ok "Agent process is running (supervisor status: $agent_status)"
        else
            print_fail "Agent process status: $agent_status"
        fi
    else
        print_fail "Cannot check agent supervisor status"
    fi
else
    print_fail "Container is not running"
fi

echo ""
echo "Verification complete"

