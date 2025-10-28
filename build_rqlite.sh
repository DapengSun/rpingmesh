#!/bin/bash

# 自定义RQLite构建脚本
set -e

IMAGE_NAME="rpingmesh-rqlite"
TAG="latest"

echo "构建自定义RQLite镜像..."

# 1. 创建RQLite专用Dockerfile
echo "1. 创建RQLite专用Dockerfile..."
cat > Dockerfile.supervisor.rqlite << 'EOF'
FROM ubuntu:22.04

# 配置清华镜像源并安装运行时依赖和supervisor
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    wget \
    ca-certificates \
    supervisor \
    bash \
    vim \
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 下载并安装RQLite
RUN wget -O /tmp/rqlite.tar.gz https://github.com/rqlite/rqlite/releases/download/v8.37.0/rqlite-v8.37.0-linux-amd64.tar.gz && \
    tar -xzf /tmp/rqlite.tar.gz -C /tmp && \
    cp /tmp/rqlite-v8.37.0-linux-amd64/rqlited /usr/local/bin/ && \
    cp /tmp/rqlite-v8.37.0-linux-amd64/rqlite /usr/local/bin/ && \
    rm -rf /tmp/rqlite* && \
    chmod +x /usr/local/bin/rqlited /usr/local/bin/rqlite

# 创建必要的目录
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /data

# 创建supervisor配置
RUN cat > /etc/supervisor/supervisord.conf << 'SUPERVISOR_EOF'
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
SUPERVISOR_EOF

# RQLite supervisor配置
RUN cat > /etc/supervisor/conf.d/rqlite.conf << 'RQLITE_EOF'
[program:rqlite]
command=/usr/local/bin/rqlited -node-id %(ENV_NODE_ID)s -http-addr 0.0.0.0:4001 -http-adv-addr %(ENV_NODE_ID)s:4001 -raft-addr 0.0.0.0:4002 -raft-adv-addr %(ENV_NODE_ID)s:4002 /data
directory=/data
autostart=true
autorestart=true
startretries=3
user=root
redirect_stderr=true
stdout_logfile=/var/log/supervisor/rqlite.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
environment=NODE_ID="rqlite-node"
RQLITE_EOF

# 创建启动脚本
RUN cat > start.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

echo "启动自定义RQLite服务..."

# 检查数据目录
if [ ! -d "/data" ]; then
    echo "创建数据目录..."
    mkdir -p /data
fi

# 设置节点ID
export NODE_ID=${NODE_ID:-"rqlite-$(hostname)"}

echo "节点ID: $NODE_ID"
echo "数据目录: /data"
echo "HTTP地址: 0.0.0.0:4001"
echo "Raft地址: 0.0.0.0:4002"

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
SCRIPT_EOF

RUN chmod +x start.sh

# 创建状态检查脚本
RUN cat > status.sh << 'STATUS_EOF'
#!/bin/bash
echo "=== RQLite 服务状态 ==="
supervisorctl status
echo ""
echo "=== 查看日志 ==="
echo "RQLite日志: tail -f /var/log/supervisor/rqlite.log"
echo "Supervisor日志: tail -f /var/log/supervisor/supervisord.log"
echo ""
echo "=== 健康检查 ==="
curl -s http://localhost:4001/status | head -5 || echo "RQLite服务未响应"
STATUS_EOF

RUN chmod +x status.sh

# 暴露端口
EXPOSE 4001 4002

# 设置环境变量
ENV NODE_ID=rqlite-node

# 设置入口点
ENTRYPOINT ["./start.sh"]
CMD []
EOF

# 2. 构建RQLite镜像
echo "2. 构建RQLite镜像..."
docker build -f Dockerfile.supervisor.rqlite -t "$IMAGE_NAME:$TAG" .

echo "RQLite镜像构建完成！"
echo
echo "镜像信息:"
docker images "$IMAGE_NAME:$TAG"

echo
echo "=== RQLite使用方法 ==="
echo "1. 保存镜像:"
echo "   docker save $IMAGE_NAME:$TAG | gzip > rqlite.tar.gz"
echo
echo "2. 在目标平台加载:"
echo "   docker load < rqlite.tar.gz"
echo
echo "3. 启动RQLite:"
echo "   docker run -d \\"
echo "     --name rqlite \\"
echo "     --network rpingmesh-network \\"
echo "     -v \$(pwd)/data:/data \\"
echo "     -e NODE_ID=rqlite-001 \\"
echo "     $IMAGE_NAME:$TAG"
echo
echo "4. 管理RQLite:"
echo "   # 查看状态"
echo "   docker exec rqlite ./status.sh"
echo
echo "   # 查看日志"
echo "   docker exec rqlite tail -f /var/log/supervisor/rqlite.log"
echo
echo "   # 重启服务"
echo "   docker exec rqlite supervisorctl restart rqlite"
echo
echo "   # 进入Shell"
echo "   docker exec -it rqlite /bin/bash"
echo
echo "   # 健康检查"
echo "   curl http://localhost:4001/status"
