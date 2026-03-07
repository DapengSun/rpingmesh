#!/bin/bash
set -e

# Script 6: Clean up server-side containers
# Stops containers without touching persistent data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[INFO] Stopping containers..."
docker compose down

echo "[INFO] Cleanup complete"

