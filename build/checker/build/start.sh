#!/bin/bash
set -e

echo "启动 R-Pingmesh Checker 容器..."

echo "启动 Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
