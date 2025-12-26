#!/bin/bash
# Build TPCC schema and start CDC components
# Flow: Wait for Oracle -> Build schema -> Enable logging -> Start CDC
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "=== Step 1/4: Waiting for Oracle setup ==="
# Check Oracle pod is running
if ! kubectl get pod -n "$NAMESPACE" -l app=${RELEASE_NAME}-oracle -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo "ERROR: Oracle pod is not running. Run 'make up' first."
    exit 1
fi

# Wait for Oracle setup with 150s timeout
TIMEOUT=150
ELAPSED=0
until kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-oracle -- ls /opt/oracle/oradata/dbinit 2>/dev/null; do
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
kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-hammerdb -- /scripts/entrypoint.sh build

echo "=== Step 3/4: Enabling supplemental logging ==="
kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-oracle -- sqlplus -S / as sysdba <<'EOF'
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER TABLE TPCC.CUSTOMER ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.DISTRICT ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.HISTORY ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ITEM ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.NEW_ORDER ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ORDER_LINE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.STOCK ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.WAREHOUSE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM ARCHIVE LOG CURRENT;
EXIT;
EOF

echo "=== Step 4/4: Starting CDC components ==="
if [ "$PROFILE" = "olr-only" ]; then
    helm upgrade "$RELEASE_NAME" chart/ \
        -n "$NAMESPACE" \
        --set mode=olr-only

    echo "  Waiting for OLR pod..."
    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s || true
    echo "  OLR started"
else
    helm upgrade "$RELEASE_NAME" chart/ \
        -n "$NAMESPACE" \
        --set mode=full

    echo "  Waiting for CDC pods..."
    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-kafka -n "$NAMESPACE" --timeout=120s || true
    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s || true
    kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-debezium -n "$NAMESPACE" --timeout=120s || true

    echo "  Waiting for Debezium streaming..."
    until kubectl logs -n "$NAMESPACE" deployment/${RELEASE_NAME}-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium is streaming"
fi

echo ""
echo "Build complete. Ready for 'make run-bench'"
