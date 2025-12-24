#!/bin/bash
# Run HammerDB benchmark with timestamp tracking in Kubernetes
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

OUTPUT_DIR="output/hammerdb"
mkdir -p "$OUTPUT_DIR"

START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/RUN_LOG_${LOG_TIMESTAMP}.txt"

echo "$START_TIME" > "$OUTPUT_DIR/RUN_START_TIME.txt"
echo "=========================================="
echo "Benchmark Start Time: $START_TIME"
echo "Log File: $LOG_FILE"
echo "Namespace: $NAMESPACE"
echo "=========================================="

kubectl exec -n "$NAMESPACE" deployment/${RELEASE_NAME}-hammerdb -- /scripts/entrypoint.sh run 2>&1 | tee "$LOG_FILE"

END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$END_TIME" > "$OUTPUT_DIR/RUN_END_TIME.txt"

echo "=========================================="
echo "Benchmark End Time: $END_TIME"
echo "Duration: $START_TIME -> $END_TIME"
echo ""
echo "To generate report:"
echo "  make report"
echo "=========================================="
