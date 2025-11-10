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
echo ""
echo "=== 节点信息 ==="
echo "节点ID: ${NODE_ID:-rqlite-$(hostname)}"
echo "数据目录: /data"
echo "HTTP地址: 0.0.0.0:4001"
echo "Raft地址: 0.0.0.0:4002"
if [ -n "$JOIN_ADDR" ]; then
    echo "集群地址: $JOIN_ADDR"
else
    echo "模式: 单节点"
fi
