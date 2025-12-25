#!/bin/bash
# Build TPCC schema and configure CDC
# Waits for Oracle, builds schema, enables supplemental logging, restarts CDC services
set -e

cd "$(dirname "$0")/../.."

echo "=== Step 1/5: Waiting for Oracle setup ==="
until docker compose exec oracle ls /opt/oracle/oradata/dbinit 2>/dev/null; do
    echo "  Waiting..."
    sleep 5
done
echo "  Oracle is ready"

# For full profile: wait for Debezium initial snapshot, then stop it
if [ "$PROFILE" = "full" ]; then
    echo "=== Step 2/5: Waiting for Debezium initial snapshot ==="
    until docker compose logs dbz 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium completed initial snapshot"
    docker compose stop dbz
else
    echo "=== Step 2/5: Skipped (olr-only profile) ==="
fi

echo "=== Step 3/5: Building TPCC schema ==="
docker compose exec -T hammerdb /scripts/entrypoint.sh build

echo "=== Step 4/5: Enabling supplemental logging ==="
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql

echo "=== Step 5/5: Restarting CDC services ==="
if [ "$PROFILE" = "olr-only" ]; then
    docker compose restart olr-file
    echo "  OLR restarted"
else
    docker compose start dbz
    docker compose restart olr-dbz dbz
    echo "  Waiting for Debezium snapshot..."
    until docker compose logs dbz --tail=100 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium is streaming"
fi

echo ""
echo "Build complete. Ready for 'make run-bench'"
