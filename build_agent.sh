#!/bin/bash

# Agent专用构建脚本
set -e

IMAGE_NAME="rpingmesh-agent"
TAG="latest"

echo "构建 R-Pingmesh Agent 镜像..."

# 1. 构建Agent二进制文件
echo "1. 构建Agent二进制文件..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing \
        git ca-certificates \
        libibverbs-dev \
        librdmacm-dev \
        clang llvm \
        libbpf-dev \
        libelf-dev \
        linux-headers-generic &&
        go mod download &&
        CGO_ENABLED=1 go build -o /workspace/agent ./cmd/agent
    "

# 2. 生成eBPF文件
echo "2. 生成eBPF文件..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing \
        git ca-certificates \
        libibverbs-dev \
        librdmacm-dev \
        clang llvm \
        libbpf-dev \
        libelf-dev \
        linux-headers-generic &&
        cd /workspace/internal/ebpf &&
        go generate ./...
    "

# 3. 创建supervisor配置
echo "3. 创建supervisor配置..."

# 创建supervisor配置目录
mkdir -p supervisor

# Agent supervisor配置
cat > supervisor/agent.conf << 'EOF'
[program:agent]
command=/app/agent --config /config/agent.yaml
directory=/app
autostart=true
autorestart=true
startretries=3
user=root
redirect_stderr=true
stdout_logfile=/var/log/supervisor/agent.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=CONFIG_DIR="/config"
EOF

# 主supervisor配置
cat > supervisor/supervisord.conf << 'EOF'
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/var/log/supervisor

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[include]
files = /etc/supervisor/conf.d/*.conf
EOF

# 4. 创建Agent专用Dockerfile
echo "4. 创建Agent专用Dockerfile..."
cat > Dockerfile.supervisor.agent << 'EOF'
FROM ubuntu:22.04

# 配置清华镜像源并安装运行时依赖和supervisor
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    libibverbs1 \
    librdmacm1 \
    iproute2 \
    supervisor \
    bash \
    vim \
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 创建必要的目录
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /config

WORKDIR /app

# 复制Agent二进制文件
COPY agent ./

# 复制eBPF文件
COPY internal/ebpf/ ./internal/ebpf/

# 复制supervisor配置
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/agent.conf /etc/supervisor/conf.d/agent.conf

# 创建启动脚本
RUN cat > start.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

echo "启动 R-Pingmesh Agent..."

# 检查配置文件
if [ ! -f "/config/agent.yaml" ]; then
    echo "错误: 配置文件 /config/agent.yaml 不存在"
    echo "请确保配置文件已正确挂载到容器中"
    exit 1
fi

echo "配置文件检查通过"
echo "启动 Supervisor..."

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
SCRIPT_EOF

RUN chmod +x start.sh

# 创建状态检查脚本
RUN cat > status.sh << 'STATUS_EOF'
#!/bin/bash
echo "=== R-Pingmesh Agent 状态 ==="
supervisorctl status
echo ""
echo "=== 查看日志 ==="
echo "Agent日志:     tail -f /var/log/supervisor/agent.log"
echo "Supervisor日志: tail -f /var/log/supervisor/supervisord.log"
STATUS_EOF

RUN chmod +x status.sh

ENTRYPOINT ["./start.sh"]
CMD []
EOF

# 5. 构建Agent镜像
echo "5. 构建Agent镜像..."
docker build -f Dockerfile.supervisor.agent -t "$IMAGE_NAME:$TAG" .

echo "Agent镜像构建完成！"
echo
echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"

echo
echo "=== Agent使用方法 ==="
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > agent.tar.gz"
echo
echo "2. 在目标平台加载:"
echo "   docker load < agent.tar.gz"
echo
echo "3. 创建配置文件:"
echo "   mkdir -p config"
echo "   cat > config/agent.yaml << 'EOF'"
echo "   controller-addr: \"controller:50051\""
echo "   analyzer-addr: \"127.0.0.1:50052\""
echo "   log-level: \"info\""
echo "   probe-interval-ms: 500"
echo "   ebpf-enabled: true"
echo "   EOF"
echo
echo "4. 启动Agent:"
echo "   docker run -d \\"
echo "     --name agent \\"
echo "     --privileged \\"
echo "     --network rpingmesh-network \\"
echo "     -v \$(pwd)/config:/config:ro \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "5. 管理Agent:"
echo "   # 查看状态"
echo "   docker exec agent ./status.sh"
echo
echo "   # 查看日志"
echo "   docker exec agent tail -f /var/log/supervisor/agent.log"
echo
echo "   # 重启服务"
echo "   docker exec agent supervisorctl restart agent"
echo
echo "   # 停止服务"
echo "   docker stop agent"
