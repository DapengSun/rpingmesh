#!/bin/bash

echo "=== R-Pingmesh 统一构建脚本 ==="
echo "构建包含Controller和Agent的统一镜像，使用supervisor管理进程"
echo

# 设置参数
IMAGE_NAME="rpingmesh-deployment"
TAG="latest"

echo "开始构建..."

# 1. 构建Controller
echo "1. 构建Controller..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates &&
        go mod download &&
        go build -o /workspace/controller ./cmd/controller
    "

# 2. 生成eBPF文件
echo "2. 生成eBPF文件..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    -e CGO_ENABLED=1 \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates libibverbs-dev librdmacm-dev clang llvm libbpf-dev libelf-dev &&
        go mod download &&
        cd internal/ebpf &&
        go generate ./...
    "

# 3. 构建Agent
echo "3. 构建Agent..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    -e CGO_ENABLED=1 \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates libibverbs-dev librdmacm-dev clang llvm libbpf-dev libelf-dev &&
        go mod download &&
        go build -o /workspace/agent ./cmd/agent
    "

# 4. 生成配置文件
echo "4. 生成配置文件..."
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    -e CGO_ENABLED=1 \
    golang:1.24-bullseye \
    sh -c "
        # 配置清华镜像源
        sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        sed -i 's/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list &&
        apt-get update && apt-get install -y --fix-missing git ca-certificates libibverbs-dev librdmacm-dev clang llvm libbpf-dev libelf-dev &&
        go mod download &&
        go build -o /workspace/temp-controller ./cmd/controller &&
        go build -o /workspace/temp-agent ./cmd/agent &&
        ./temp-controller --create-config --config-output /workspace/controller.yaml &&
        ./temp-agent --create-config --config-output /workspace/agent.yaml &&
        rm temp-controller temp-agent
    "

# 5. 创建supervisor配置
echo "5. 创建supervisor配置..."

# 创建supervisor配置目录
mkdir -p supervisor

# Controller supervisor配置
cat > supervisor/controller.conf << 'EOF'
[program:controller]
command=/app/controller --config /config/controller.yaml
directory=/app
autostart=true
autorestart=true
startretries=3
user=root
redirect_stderr=true
stdout_logfile=/var/log/supervisor/controller.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=CONFIG_DIR="/config"
EOF

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

# 6. 创建Dockerfile
echo "6. 创建Dockerfile..."
cat > Dockerfile.simple << 'EOF'
FROM ubuntu:22.04

# 配置清华镜像源并安装运行时依赖和supervisor
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    libibverbs1 \
    librdmacm1 \
    iproute2 \
    supervisor \
    vim \
    net-tools \
    iputils-ping \
    bash \
    && rm -rf /var/lib/apt/lists/*

# 创建必要的目录
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /config

WORKDIR /app

# 复制二进制文件
COPY controller agent ./

# 复制eBPF文件
COPY internal/ebpf/ ./internal/ebpf/

# 复制supervisor配置
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/controller.conf /etc/supervisor/conf.d/controller.conf
COPY supervisor/agent.conf /etc/supervisor/conf.d/agent.conf

# 创建启动脚本
RUN cat > start.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

echo "启动 R-Pingmesh 服务..."

# 检查配置文件
if [ ! -f "/config/controller.yaml" ]; then
    echo "错误: 缺少 /config/controller.yaml 配置文件"
    echo "请使用: docker run -v \$(pwd)/config:/config <image>"
    exit 1
fi

if [ ! -f "/config/agent.yaml" ]; then
    echo "错误: 缺少 /config/agent.yaml 配置文件"
    echo "请使用: docker run -v \$(pwd)/config:/config <image>"
    exit 1
fi

echo "配置文件检查通过"
echo "启动 Supervisor..."

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
SCRIPT_EOF

RUN chmod +x start.sh

# 创建简单的状态检查脚本
RUN cat > status.sh << 'STATUS_EOF'
#!/bin/bash
echo "=== R-Pingmesh 服务状态 ==="
supervisorctl status
echo ""
echo "=== 查看日志 ==="
echo "Controller日志: tail -f /var/log/supervisor/controller.log"
echo "Agent日志:     tail -f /var/log/supervisor/agent.log"
echo "Supervisor日志: tail -f /var/log/supervisor/supervisord.log"
STATUS_EOF

RUN chmod +x status.sh

ENTRYPOINT ["./start.sh"]
CMD []
EOF

# 7. 构建镜像
echo "7. 构建Docker镜像..."
docker build -f Dockerfile.simple -t "$IMAGE_NAME:$TAG" .

# 8. 创建配置目录（仅创建目录，配置文件由用户提供）
echo "8. 创建配置目录..."
mkdir -p config

echo "构建完成！"
echo
echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"
