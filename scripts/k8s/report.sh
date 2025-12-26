#!/bin/bash
# Generate performance report from Kubernetes metrics
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"

OUTPUT_DIR="$PROJECT_ROOT/output/hammerdb"
REPORT_GEN="$PROJECT_ROOT/scripts/report-generator/k8s_report.py"

if [[ ! -f "$OUTPUT_DIR/RUN_START_TIME.txt" ]] || [[ ! -f "$OUTPUT_DIR/RUN_END_TIME.txt" ]]; then
    echo "Error: No benchmark timestamps found in $OUTPUT_DIR"
    echo "Run 'make run-bench' first to generate benchmark data."
    exit 1
fi

START_TIME=$(cat "$OUTPUT_DIR/RUN_START_TIME.txt")
END_TIME=$(cat "$OUTPUT_DIR/RUN_END_TIME.txt")

REPORT_DIR="$PROJECT_ROOT/reports/performance/$(date +%Y%m%d_%H%M)"
mkdir -p "$REPORT_DIR"

# Detect profile from PROFILE env var or default to full
PROFILE="${PROFILE:-full}"

# Set containers based on profile
if [ "$PROFILE" = "olr-only" ]; then
    CONTAINERS="oracle,olr"
else
    CONTAINERS="oracle,olr,debezium,kafka,kafka-consumer"
fi

echo "=========================================="
echo "Generating Performance Report (Kubernetes)"
echo "Profile: $PROFILE"
echo "Containers: $CONTAINERS"
echo "Start: $START_TIME"
echo "End:   $END_TIME"
echo "Namespace: $NAMESPACE"
echo "Output: $REPORT_DIR/report.html"
echo "=========================================="

# Common metrics for all profiles
COMMON_METRICS=(
    --rate-of 'oracledb_activity_user_commits'
    --rate-of 'oracledb_dml_redo_entries'
    --rate-of 'dml_ops{filter="out"}'
    --rate-of 'messages_sent'
)

# Additional metrics for full profile
FULL_METRICS=(
    --rate-of 'debezium_oracle_streaming_total_captured_dml'
    --rate-of 'kafka_topic_partition_current_offset{topic=~"oracle.*"}'
    --rate-of 'kafka_consumergroup_current_offset{consumergroup="file-writer"}'
)

if [ "$PROFILE" = "full" ]; then
    python3 "$REPORT_GEN" \
        --start "$START_TIME" \
        --end "$END_TIME" \
        --containers "$CONTAINERS" \
        --namespace "$NAMESPACE" \
        "${COMMON_METRICS[@]}" \
        "${FULL_METRICS[@]}" \
        --output "$REPORT_DIR/report.html" \
        --title "K8s Performance Test $(date +%Y-%m-%d) ($PROFILE)"
else
    python3 "$REPORT_GEN" \
        --start "$START_TIME" \
        --end "$END_TIME" \
        --containers "$CONTAINERS" \
        --namespace "$NAMESPACE" \
        "${COMMON_METRICS[@]}" \
        --output "$REPORT_DIR/report.html" \
        --title "K8s Performance Test $(date +%Y-%m-%d) ($PROFILE)"
fi

echo "=========================================="
echo "Report generated: $REPORT_DIR/report.html"
echo "=========================================="
