#!/bin/bash
# Generate performance report from last benchmark run
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

OUTPUT_DIR="$PROJECT_ROOT/output/hammerdb"
REPORT_GEN="$PROJECT_ROOT/scripts/report-generator/generate_report.py"

if [[ ! -f "$OUTPUT_DIR/RUN_START_TIME.txt" ]] || [[ ! -f "$OUTPUT_DIR/RUN_END_TIME.txt" ]]; then
    echo "Error: No benchmark timestamps found in $OUTPUT_DIR"
    echo "Run 'make run-bench' first to generate benchmark data."
    exit 1
fi

START_TIME=$(cat "$OUTPUT_DIR/RUN_START_TIME.txt")
END_TIME=$(cat "$OUTPUT_DIR/RUN_END_TIME.txt")

REPORT_DIR="$PROJECT_ROOT/reports/performance/$(date +%Y%m%d_%H%M)"
mkdir -p "$REPORT_DIR"

# Auto-detect active profile based on running containers
if docker compose ps --format '{{.Names}}' 2>/dev/null | grep -q "olr-file"; then
    # olr-only profile
    CONTAINERS="oracle,olr-file"
    PROFILE="olr-only"
elif docker compose ps --format '{{.Names}}' 2>/dev/null | grep -q "olr-dbz"; then
    # full profile
    CONTAINERS="oracle,olr-dbz,dbz,kafka,kafka-consumer"
    PROFILE="full"
else
    # fallback to oracle only
    CONTAINERS="oracle"
    PROFILE="base"
fi

echo "=========================================="
echo "Generating Performance Report"
echo "Profile: $PROFILE"
echo "Containers: $CONTAINERS"
echo "Start: $START_TIME"
echo "End:   $END_TIME"
echo "Output: $REPORT_DIR/report.html"
echo "=========================================="

python3 "$REPORT_GEN" \
    --start "$START_TIME" \
    --end "$END_TIME" \
    --containers "$CONTAINERS" \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'oracledb_dml_redo_entries' \
    --rate-of 'oracledb_activity_user_commits' \
    --total-of 'bytes_sent' \
    --total-of 'messages_sent' \
    --output "$REPORT_DIR/report.html" \
    --title "Performance Test $(date +%Y-%m-%d) ($PROFILE)"

echo "=========================================="
echo "Report generated: $REPORT_DIR/report.html"
echo "=========================================="
