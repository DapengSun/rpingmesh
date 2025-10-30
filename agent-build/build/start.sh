#!/bin/bash
set -e

echo "启动 R-Pingmesh Agent..."

# 检查配置文件
if [ ! -f "/app/config/agent.yaml" ]; then
    echo "错误: 配置文件 /app/config/agent.yaml 不存在"
    echo "请确保配置文件已正确挂载到容器中"
    ls -R /app
    exit 1
fi

echo "配置文件检查通过"
echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2
echo "启动 Supervisor..."

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf


