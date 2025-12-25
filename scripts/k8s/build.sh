#!/bin/bash
# Build TPCC schema and configure CDC in Kubernetes
# Waits for Oracle, builds schema, enables supplemental logging, restarts CDC services
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "=== Step 1/5: Waiting for Oracle setup ==="
until kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-oracle -- ls /opt/oracle/oradata/dbinit 2>/dev/null; do
    echo "  Waiting..."
    sleep 5
done
echo "  Oracle is ready"

# For full profile: wait for Debezium initial snapshot
if [ "$PROFILE" = "full" ]; then
    echo "=== Step 2/5: Waiting for Debezium initial snapshot ==="
    until kubectl logs -n "$NAMESPACE" deployment/${RELEASE_NAME}-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium completed initial snapshot"
else
    echo "=== Step 2/5: Skipped (olr-only profile) ==="
fi

echo "=== Step 3/5: Building TPCC schema ==="
kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-hammerdb -- /scripts/entrypoint.sh build

echo "=== Step 4/5: Enabling supplemental logging ==="
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

echo "=== Step 5/5: Restarting CDC services ==="
if [ "$PROFILE" = "olr-only" ]; then
    kubectl rollout restart deployment/${RELEASE_NAME}-olr -n "$NAMESPACE"
    kubectl rollout status deployment/${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s
    echo "  OLR restarted"
else
    kubectl rollout restart deployment/${RELEASE_NAME}-olr deployment/${RELEASE_NAME}-debezium -n "$NAMESPACE"
    kubectl rollout status deployment/${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s
    kubectl rollout status deployment/${RELEASE_NAME}-debezium -n "$NAMESPACE" --timeout=120s
    echo "  Waiting for Debezium snapshot..."
    until kubectl logs -n "$NAMESPACE" deployment/${RELEASE_NAME}-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
        echo "  Waiting..."
        sleep 10
    done
    echo "  Debezium is streaming"
fi

echo ""
echo "Build complete. Ready for 'make run-bench'"
