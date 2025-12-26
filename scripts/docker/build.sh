#!/bin/bash
# Build TPCC schema and start CDC components
# Flow: Wait for Oracle -> Build schema -> Enable logging -> Start CDC
set -e

cd "$(dirname "$0")/../.."

echo "=== Step 1/4: Waiting for Oracle setup ==="
# Check Oracle container is running
if ! docker compose ps oracle --format '{{.State}}' 2>/dev/null | grep -q "running"; then
    echo "ERROR: Oracle container is not running. Run 'make up' first."
    exit 1
fi

# Wait for Oracle setup with 150s timeout
TIMEOUT=150
ELAPSED=0
until docker compose exec oracle ls /opt/oracle/oradata/dbinit 2>/dev/null; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Timeout waiting for Oracle setup (${TIMEOUT}s)"
        exit 1
    fi
    echo "  Waiting... (${ELAPSED}s/${TIMEOUT}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo "  Oracle is ready"

echo "=== Step 2/4: Building TPCC schema ==="
docker compose exec -T hammerdb /scripts/entrypoint.sh build

echo "=== Step 3/4: Enabling supplemental logging ==="
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql

echo "=== Step 4/4: Starting CDC components ==="
if [ "$PROFILE" = "olr-only" ]; then
    docker compose --profile=olr-only up -d olr-file
    echo "  OLR started"
else
    docker compose --profile=full up -d
    echo "  Waiting for Debezium streaming..."
    until docker compose logs dbz --tail=100 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium is streaming"
fi

echo ""
echo "Build complete. Ready for 'make run-bench'"
