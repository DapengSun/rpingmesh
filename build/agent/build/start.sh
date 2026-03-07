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

BUILD_USER=${BUILD_USER:-rpingmesh}
BUILD_GROUP=${BUILD_GROUP:-rpingmesh}
BUILD_UID=${BUILD_UID:-2133}
BUILD_GID=${BUILD_GID:-2015}

# 持久化目录结构
PERSISTENT_BASE="/private/rpingmesh/agent"
PERSISTENT_DATA_DIR="$PERSISTENT_BASE/data"
PERSISTENT_CONFIG_DIR="$PERSISTENT_BASE/config"

# 创建持久化目录
mkdir -p "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR"
chown -R "${BUILD_UID}:${BUILD_GID}" "$PERSISTENT_BASE" || true

# 检查配置文件是否已挂载（通过 bind mount）
CONFIG_FILE_TARGET="$PERSISTENT_CONFIG_DIR/agent.yaml"
CONFIG_SOURCE="/mnt/config-source/agent.yaml"

# 如果配置文件源存在（通过 bind mount 挂载），则复制到持久化目录（仅当目标文件不存在时）
if [ -f "$CONFIG_SOURCE" ] && [ -s "$CONFIG_SOURCE" ]; then
    echo "信息: 检测到配置文件源: $CONFIG_SOURCE"
    if [ ! -f "$CONFIG_FILE_TARGET" ]; then
        # 目标文件不存在，复制配置文件到持久化目录
        cp "$CONFIG_SOURCE" "$CONFIG_FILE_TARGET"
        # 设置配置文件权限为 BUILD_UID:BUILD_GID
        chown "${BUILD_UID}:${BUILD_GID}" "$CONFIG_FILE_TARGET" || true
        echo "信息: 已将配置文件复制到持久化目录: $CONFIG_FILE_TARGET"
    else
        # 目标文件已存在，不覆盖
        echo "信息: 配置文件已存在，跳过复制: $CONFIG_FILE_TARGET"
        if [ ! -s "$CONFIG_FILE_TARGET" ]; then
            echo "警告: 配置文件存在但为空: $CONFIG_FILE_TARGET"
            echo "请检查配置文件是否正确"
        fi
    fi
elif [ -f "$CONFIG_FILE_TARGET" ]; then
    # 如果持久化目录中已有配置文件，检查是否有内容
    if [ -s "$CONFIG_FILE_TARGET" ]; then
        echo "信息: 使用持久化目录中的配置文件: $CONFIG_FILE_TARGET"
    else
        echo "警告: 配置文件存在但为空: $CONFIG_FILE_TARGET"
        echo "请检查配置文件是否正确"
    fi
fi

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
chown -R "${BUILD_UID}:${BUILD_GID}" "$PERSISTENT_DATA_DIR" "$PERSISTENT_CONFIG_DIR" || true

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
    # Fix: Use non-greedy pattern to match only the key-value separator, not colons in the value
    # Pattern: match key (non-colon chars), then colon, then optional spaces, then quoted or unquoted value
    CONFIG_CONTROLLER_ADDR=$(grep -E "^\s*(controller-addr|controller_addr):" "$CONFIG_FILE" | head -1 | sed -E 's/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' | tr -d ' ')
    CONFIG_ANALYZER_ADDR=$(grep -E "^\s*(analyzer-addr|analyzer_addr):" "$CONFIG_FILE" | head -1 | sed -E 's/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' | tr -d ' ')
    CONFIG_ANALYZER_ENABLED=$(grep -E "^\s*(analyzer-enabled|analyzer_enabled):" "$CONFIG_FILE" | head -1 | sed -E 's/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    # Extract otel-collector-addr (format: grpc://host:port or http://host:port)
    CONFIG_OTEL_COLLECTOR_ADDR=$(grep -E "^\s*(otel-collector-addr|otel_collector_addr):" "$CONFIG_FILE" | head -1 | sed -E 's/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' | tr -d ' ')
    # Extract metrics-enabled
    CONFIG_METRICS_ENABLED=$(grep -E "^\s*(metrics-enabled|metrics_enabled):" "$CONFIG_FILE" | head -1 | sed -E 's/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
fi

# Priority: environment variable > config file > default
CONTROLLER_ADDR="${RPINGMESH_CONTROLLER_ADDR:-${CONFIG_CONTROLLER_ADDR:-controller:50051}}"
ANALYZER_ADDR="${RPINGMESH_ANALYZER_ADDR:-${CONFIG_ANALYZER_ADDR:-localhost:50052}}"
OTEL_COLLECTOR_ADDR="${RPINGMESH_OTEL_COLLECTOR_ADDR:-${CONFIG_OTEL_COLLECTOR_ADDR:-grpc://localhost:4317}}"

# Function to parse address and extract host and port
# If address doesn't contain ':', treat it as port only and use default host
# Also handles :port format (empty host means use default)
# Supports IPv6 addresses in brackets (e.g., [::1]:50051)
# Supports protocol prefix (e.g., grpc://host:port, http://host:port)
parse_address() {
    local addr=$1
    local default_host=$2
    local host
    local port
    
    # Remove protocol prefix if present (grpc://, http://, https://)
    addr=$(echo "$addr" | sed -E 's|^[a-zA-Z]+://||')
    
    # Handle IPv6 addresses in brackets (e.g., [::1]:50051)
    if [[ "$addr" == \[*\]:* ]]; then
        # Extract IPv6 address and port
        host=$(echo "$addr" | sed 's/^\[\([^]]*\)\]:.*$/\1/')
        port=$(echo "$addr" | sed 's/^\[[^]]*\]:\(.*\)$/\1/')
    elif [[ "$addr" == *:* ]]; then
        # Regular IPv4 or hostname:port format
        host=$(echo "$addr" | cut -d':' -f1)
        port=$(echo "$addr" | cut -d':' -f2-)
        # If host is empty (e.g., :50051), use default host
        if [ -z "$host" ]; then
            host="$default_host"
        fi
    else
        # No colon found, treat as port only
        host="$default_host"
        port="$addr"
    fi
    
    # Validate that we have both host and port
    if [ -z "$host" ] || [ -z "$port" ]; then
        echo "ERROR: Invalid address format: $addr (expected format: host:port or :port)" >&2
        return 1
    fi
    
    echo "$host|$port"
}

# Parse addresses
CONTROLLER_PARSED=$(parse_address "$CONTROLLER_ADDR" "controller")
if [ $? -ne 0 ]; then
    echo "Failed to parse Controller address: $CONTROLLER_ADDR" >&2
    exit 1
fi
CONTROLLER_HOST=$(echo "$CONTROLLER_PARSED" | cut -d'|' -f1)
CONTROLLER_PORT=$(echo "$CONTROLLER_PARSED" | cut -d'|' -f2)

ANALYZER_PARSED=$(parse_address "$ANALYZER_ADDR" "localhost")
if [ $? -ne 0 ]; then
    echo "Failed to parse Analyzer address: $ANALYZER_ADDR" >&2
    exit 1
fi
ANALYZER_HOST=$(echo "$ANALYZER_PARSED" | cut -d'|' -f1)
ANALYZER_PORT=$(echo "$ANALYZER_PARSED" | cut -d'|' -f2)

# Parse otel-collector address (format: grpc://host:port or http://host:port)
OTEL_COLLECTOR_PARSED=$(parse_address "$OTEL_COLLECTOR_ADDR" "localhost")
if [ $? -ne 0 ]; then
    echo "Failed to parse Otel-Collector address: $OTEL_COLLECTOR_ADDR" >&2
    # Don't exit, just skip otel-collector test
    OTEL_COLLECTOR_HOST=""
    OTEL_COLLECTOR_PORT=""
else
    OTEL_COLLECTOR_HOST=$(echo "$OTEL_COLLECTOR_PARSED" | cut -d'|' -f1)
    OTEL_COLLECTOR_PORT=$(echo "$OTEL_COLLECTOR_PARSED" | cut -d'|' -f2)
fi

echo "Controller: $CONTROLLER_ADDR (host: $CONTROLLER_HOST, port: $CONTROLLER_PORT)"
echo "Analyzer: $ANALYZER_ADDR (host: $ANALYZER_HOST, port: $ANALYZER_PORT)"
if [ -n "$OTEL_COLLECTOR_HOST" ] && [ -n "$OTEL_COLLECTOR_PORT" ]; then
    echo "Otel-Collector: $OTEL_COLLECTOR_ADDR (host: $OTEL_COLLECTOR_HOST, port: $OTEL_COLLECTOR_PORT)"
fi
echo

# Function to test connectivity with multiple methods
test_connectivity() {
    local name=$1
    local host=$2
    local port=$3
    local success=false
    
    echo "=== Testing $name connectivity ($host:$port) ==="
    
    # Test 1: Ping test (only for IP addresses or resolved hosts)
    echo "1. Ping test (if applicable)..."
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
    
    # Test 2: Netcat test
    echo "2. Netcat (nc) connectivity test..."
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
    
    # Test 3: Telnet test
    echo "3. Telnet connectivity test..."
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

# Test Otel-Collector connectivity (only if metrics are enabled and address is configured)
METRICS_ENABLED_FINAL="${RPINGMESH_METRICS_ENABLED:-${CONFIG_METRICS_ENABLED:-true}}"
if [ "$METRICS_ENABLED_FINAL" = "true" ] || [ "$METRICS_ENABLED_FINAL" = "True" ] || [ "$METRICS_ENABLED_FINAL" = "1" ]; then
    if [ -n "$OTEL_COLLECTOR_HOST" ] && [ -n "$OTEL_COLLECTOR_PORT" ]; then
        echo "=== Otel-Collector Connectivity Test ==="
        echo "Metrics enabled: $METRICS_ENABLED_FINAL"
        echo "Otel-Collector address: $OTEL_COLLECTOR_ADDR (host: $OTEL_COLLECTOR_HOST, port: $OTEL_COLLECTOR_PORT)"
        echo
        test_connectivity "Otel-Collector" "$OTEL_COLLECTOR_HOST" "$OTEL_COLLECTOR_PORT"
    else
        echo "=== Otel-Collector Connectivity Test ==="
        echo "Skipped: Otel-Collector address not configured"
        echo "  OTEL_COLLECTOR_HOST: ${OTEL_COLLECTOR_HOST:-<empty>}"
        echo "  OTEL_COLLECTOR_PORT: ${OTEL_COLLECTOR_PORT:-<empty>}"
        echo "  OTEL_COLLECTOR_ADDR: ${OTEL_COLLECTOR_ADDR:-<empty>}"
        echo "(Set otel-collector-addr in config file to enable)"
        echo
    fi
else
    echo "=== Otel-Collector Connectivity Test ==="
    echo "Skipped: Metrics are not enabled"
    echo "  metrics-enabled: $METRICS_ENABLED_FINAL"
    echo "(Set metrics-enabled: true in config file or RPINGMESH_METRICS_ENABLED=true to enable)"
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
