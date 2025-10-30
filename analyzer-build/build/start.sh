#!/bin/bash
set -e

: ${LISTEN_ADDR:=0.0.0.0:50052}
export LISTEN_ADDR

if [ -z "$DATABASE_URI" ]; then
  echo "[analyzer] Warning: DATABASE_URI is empty; set -e DATABASE_URI=http://rqlite:4001 if using rqlite in same network"
else
  echo "[analyzer] DATABASE_URI=$DATABASE_URI"
fi

echo "[analyzer] LISTEN_ADDR=$LISTEN_ADDR"

# start SSH like other components
echo "启动SSH服务..."
/etc/init.d/ssh-start &
sleep 2

echo "启动 Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
