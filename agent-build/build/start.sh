#!/bin/bash
set -e

# Get agent directory path from environment variable (default: /app for backward compatibility)
RPINGMESH_AGENT_DIR_PATH="${RPINGMESH_AGENT_DIR_PATH:-/app}"
CONFIG_FILE="${RPINGMESH_AGENT_DIR_PATH}/config/agent.yaml"

echo "=========================================="
echo "R-Pingmesh Agent Startup"
echo "=========================================="
echo "Timestamp: $(date -Iseconds)"
echo

echo "启动 R-Pingmesh Agent..."

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/agent"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"

# 创建软链接：/app/data -> /private/rpingmesh/agent/data
if [ -L "/app/data" ] || [ -e "/app/data" ]; then
    rm -rf "/app/data"
fi
ln -sf "$PERSISTENT_DATA_DIR" "/app/data"

# 创建软链接：/app/config -> /private/rpingmesh/agent/config
if [ -L "/app/config" ] || [ -e "/app/config" ]; then
    rm -rf "/app/config"
fi
ln -sf "$PERSISTENT_CONFIG_DIR" "/app/config"

echo "--- Configuration Source ---"
echo "RPINGMESH_AGENT_DIR_PATH=${RPINGMESH_AGENT_DIR_PATH}"
echo "Config File: ${CONFIG_FILE}"
echo ""
echo "Note: Configuration is loaded from agent.yaml file."
echo "Environment variables (RPINGMESH_*) can optionally override config values."
echo "Environment variables set:"
echo "  RPINGMESH_CONTROLLER_ADDR=${RPINGMESH_CONTROLLER_ADDR:-<not set, will use config>}"
echo "  RPINGMESH_ANALYZER_ADDR=${RPINGMESH_ANALYZER_ADDR:-<not set, will use config>}"
echo "  RPINGMESH_ANALYZER_ENABLED=${RPINGMESH_ANALYZER_ENABLED:-<not set, will use config>}"
echo

# 检查配置文件 - 和 controller 一样，如果不存在则抛出错误
if [ ! -f "/app/config/agent.yaml" ]; then
    echo "错误: 配置文件 /app/config/agent.yaml 不存在"
    echo "请确保配置文件已正确挂载到容器中"
    echo "RPINGMESH_AGENT_DIR_PATH=${RPINGMESH_AGENT_DIR_PATH}"
    if [ -d "$RPINGMESH_AGENT_DIR_PATH" ]; then
        echo "Directory contents:"
        ls -R "$RPINGMESH_AGENT_DIR_PATH" 2>&1 || true
    else
        echo "Directory $RPINGMESH_AGENT_DIR_PATH does not exist"
    fi
    exit 1
fi
echo "配置文件检查通过: $CONFIG_FILE"
echo "Configuration file contents:"
cat "$CONFIG_FILE"
echo

echo "--- Network Connectivity Tests ---"
# Extract addresses from config file (with fallback to environment or defaults)
# Try to read from config file first
if [ -f "$CONFIG_FILE" ]; then
    # Try to extract controller-addr from config file (supports both kebab-case and snake_case)
    CONFIG_CONTROLLER_ADDR=$(grep -E "^\s*(controller-addr|controller_addr):" "$CONFIG_FILE" | head -1 | sed 's/.*:\s*"*\([^"]*\)"*/\1/' | tr -d ' ')
    CONFIG_ANALYZER_ADDR=$(grep -E "^\s*(analyzer-addr|analyzer_addr):" "$CONFIG_FILE" | head -1 | sed 's/.*:\s*"*\([^"]*\)"*/\1/' | tr -d ' ')
    CONFIG_ANALYZER_ENABLED=$(grep -E "^\s*(analyzer-enabled|analyzer_enabled):" "$CONFIG_FILE" | head -1 | sed 's/.*:\s*\(.*\)/\1/' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
fi

# Priority: environment variable > config file > default
CONTROLLER_ADDR="${RPINGMESH_CONTROLLER_ADDR:-${CONFIG_CONTROLLER_ADDR:-controller:50051}}"
ANALYZER_ADDR="${RPINGMESH_ANALYZER_ADDR:-${CONFIG_ANALYZER_ADDR:-localhost:50052}}"

# Try to extract host and port
CONTROLLER_HOST=$(echo "$CONTROLLER_ADDR" | cut -d':' -f1)
CONTROLLER_PORT=$(echo "$CONTROLLER_ADDR" | cut -d':' -f2)
ANALYZER_HOST=$(echo "$ANALYZER_ADDR" | cut -d':' -f1)
ANALYZER_PORT=$(echo "$ANALYZER_ADDR" | cut -d':' -f2)

echo "Controller: $CONTROLLER_ADDR (host: $CONTROLLER_HOST, port: $CONTROLLER_PORT)"
echo "Analyzer: $ANALYZER_ADDR (host: $ANALYZER_HOST, port: $ANALYZER_PORT)"
echo

# Function to test connectivity with multiple methods
test_connectivity() {
    local name=$1
    local host=$2
    local port=$3
    local success=false
    
    echo "=== Testing $name connectivity ($host:$port) ==="
    
    # Test 1: DNS resolution
    echo "1. DNS resolution test..."
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup "$host" >/dev/null 2>&1; then
            echo "   ✓ DNS resolution successful"
            nslookup "$host" 2>&1 | grep -E "Name:|Address:" | head -3 || true
        else
            echo "   ✗ DNS resolution failed for $host"
            echo "   Note: This might be normal if $host is an IP address or localhost"
        fi
    fi
    echo
    
    # Test 2: Ping test (only for IP addresses or resolved hosts)
    echo "2. Ping test (if applicable)..."
    if command -v ping >/dev/null 2>&1; then
        # Try to ping if it looks like an IP or if DNS resolved
        if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$host" =~ ^localhost$ ]]; then
            if timeout 2 ping -c 1 "$host" >/dev/null 2>&1; then
                echo "   ✓ Host is reachable via ping"
            else
                echo "   ✗ Host not reachable via ping"
            fi
        else
            echo "   (Skipped: hostname may require DNS resolution)"
        fi
    fi
    echo
    
    # Test 3: Netcat test
    echo "3. Netcat (nc) connectivity test..."
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -zv "$host" "$port" 2>&1; then
            echo "   ✓ $name connection successful via netcat"
            success=true
        else
            echo "   ✗ $name connection failed via netcat"
            echo "   Error details:"
            timeout 3 nc -zv "$host" "$port" 2>&1 || true
        fi
    else
        echo "   (nc not available)"
    fi
    echo
    
    # Test 4: Telnet test
    echo "4. Telnet connectivity test..."
    if command -v telnet >/dev/null 2>&1; then
        # Telnet doesn't have a good timeout mechanism, so use a small timeout with expect-like behavior
        if timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo "   ✓ $name connection successful (TCP test)"
            success=true
        else
            echo "   ✗ $name connection failed (TCP test)"
        fi
    else
        echo "   (telnet not available, using bash TCP test)"
        if timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo "   ✓ $name connection successful (bash TCP test)"
            success=true
        else
            echo "   ✗ $name connection failed (bash TCP test)"
        fi
    fi
    echo
    
    # Test 5: gRPC specific test (using curl if available)
    echo "5. gRPC endpoint test..."
    if command -v curl >/dev/null 2>&1; then
        # Try HTTP/2 connection (gRPC uses HTTP/2)
        if timeout 3 curl -sSf --http2 "http://$host:$port" >/dev/null 2>&1; then
            echo "   ✓ HTTP/2 connection successful (gRPC compatible)"
            success=true
        else
            # Fallback to HTTP/1.1
            if timeout 3 curl -sSf "http://$host:$port" >/dev/null 2>&1; then
                echo "   ⚠ HTTP connection successful but may not be gRPC"
            else
                echo "   ✗ HTTP connection failed"
                echo "   Note: This is expected for gRPC endpoints - gRPC requires proper handshake"
            fi
        fi
    else
        echo "   (curl not available)"
    fi
    echo
    
    # Summary
    echo "=== $name Connectivity Summary ==="
    if [ "$success" = true ]; then
        echo "✓ $name is reachable"
    else
        echo "✗ $name is NOT reachable"
        echo "  Troubleshooting tips:"
        echo "  - Check if $name service is running"
        echo "  - Verify network connectivity between containers"
        echo "  - Check firewall rules"
        echo "  - Verify DNS resolution (if using hostname)"
        if [ "$name" = "Analyzer" ] && [ "${RPINGMESH_ANALYZER_ENABLED:-false}" = "true" ]; then
            echo "  ⚠ WARNING: Analyzer is enabled but not reachable - uploads will fail!"
        fi
    fi
    echo
}

# Test Controller connectivity
test_connectivity "Controller" "$CONTROLLER_HOST" "$CONTROLLER_PORT"

# Determine if analyzer is enabled (priority: env > config > default)
ANALYZER_ENABLED_FINAL="${RPINGMESH_ANALYZER_ENABLED:-${CONFIG_ANALYZER_ENABLED:-false}}"
if [ "$ANALYZER_ENABLED_FINAL" = "true" ] || [ "$ANALYZER_ENABLED_FINAL" = "True" ] || [ "$ANALYZER_ENABLED_FINAL" = "1" ]; then
    test_connectivity "Analyzer" "$ANALYZER_HOST" "$ANALYZER_PORT"
else
    echo "=== Analyzer Connectivity Test ==="
    echo "Skipped: Analyzer is not enabled"
    echo "(Set analyzer-enabled: true in config file or RPINGMESH_ANALYZER_ENABLED=true to enable)"
    echo
fi

echo "--- Analyzer Configuration Summary ---"
echo "Effective analyzer-enabled setting: ${ANALYZER_ENABLED_FINAL:-false}"
if [ -n "$RPINGMESH_ANALYZER_ENABLED" ]; then
    echo "  Source: Environment variable (RPINGMESH_ANALYZER_ENABLED)"
elif [ -n "$CONFIG_ANALYZER_ENABLED" ]; then
    echo "  Source: Configuration file (analyzer-enabled)"
else
    echo "  Source: Default value (false)"
fi
if [ "$ANALYZER_ENABLED_FINAL" != "true" ] && [ "$ANALYZER_ENABLED_FINAL" != "True" ] && [ "$ANALYZER_ENABLED_FINAL" != "1" ]; then
    echo "⚠ WARNING: Analyzer is disabled - no data will be uploaded to Analyzer!"
fi
echo

echo "--- System Information ---"
echo "Hostname: $(hostname)"
echo "Container IP: $(hostname -I 2>/dev/null || ip addr show | grep -E 'inet ' | head -1 || echo 'unknown')"
echo "Agent Directory Path: $RPINGMESH_AGENT_DIR_PATH"
echo

echo "--- RDMA Device Detection ---"
echo "Checking RDMA device availability..."

# Check if running with privileged mode (required for RDMA)
if [ -d /dev/infiniband ] && [ "$(ls -A /dev/infiniband 2>/dev/null)" ]; then
    echo "✓ /dev/infiniband directory exists and contains devices:"
    ls -la /dev/infiniband/ 2>/dev/null | head -10 || echo "  (cannot list contents)"
else
    echo "✗ /dev/infiniband directory missing or empty"
    echo "  WARNING: RDMA devices may not be accessible!"
    echo "  This usually means the container is not running with --privileged flag"
fi

# Check RDMA libraries
if ldconfig -p 2>/dev/null | grep -q libibverbs; then
    echo "✓ libibverbs library found"
    ldconfig -p 2>/dev/null | grep libibverbs | head -3 || true
else
    echo "✗ libibverbs library not found"
fi

if ldconfig -p 2>/dev/null | grep -q librdmacm; then
    echo "✓ librdmacm library found"
    ldconfig -p 2>/dev/null | grep librdmacm | head -3 || true
else
    echo "✗ librdmacm library not found"
fi

# Check if ibv_devices command is available (optional utility)
if command -v ibv_devices >/dev/null 2>&1; then
    echo "✓ ibv_devices command available"
    echo "  Attempting to list RDMA devices:"
    timeout 2 ibv_devices 2>&1 || echo "  (ibv_devices command failed or timed out)"
else
    echo "⚠ ibv_devices command not available (optional - requires ibverbs-utils package)"
fi

echo "--- Starting SSH Service ---"
/etc/init.d/ssh-start &
sleep 2
echo "SSH service started"
echo

echo "--- Starting Supervisor ---"
echo "Agent will start with the following configuration:"
echo "  - Agent Directory: $RPINGMESH_AGENT_DIR_PATH"
echo "  - Config file: $CONFIG_FILE"
if [ -n "$RPINGMESH_CONTROLLER_ADDR" ]; then
    echo "  - Controller: ${CONTROLLER_ADDR} (from environment variable)"
else
    echo "  - Controller: ${CONTROLLER_ADDR} (from config file)"
fi
if [ -n "$RPINGMESH_ANALYZER_ADDR" ]; then
    echo "  - Analyzer: ${ANALYZER_ADDR} (from environment variable)"
else
    echo "  - Analyzer: ${ANALYZER_ADDR} (from config file)"
fi
if [ -n "$RPINGMESH_ANALYZER_ENABLED" ]; then
    echo "  - Analyzer Enabled: ${ANALYZER_ENABLED_FINAL:-false} (from environment variable)"
else
    echo "  - Analyzer Enabled: ${ANALYZER_ENABLED_FINAL:-false} (from config file)"
fi
echo ""
echo "Note: All configuration values are loaded from agent.yaml"
echo "      Environment variables (RPINGMESH_*) can override config file values"
echo

echo "=========================================="
echo "Starting Supervisor..."
echo "=========================================="
echo

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
