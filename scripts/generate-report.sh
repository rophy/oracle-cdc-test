#!/bin/bash
#
# Generate performance report from the last benchmark run.
#
# Reads timestamps from:
#   - output/hammerdb/RUN_START_TIME.txt
#   - output/hammerdb/RUN_END_TIME.txt
#
# Auto-detects active profile (olr-only or full) and selects appropriate containers.
#

set -e

OUTPUT_DIR="output/hammerdb"
START_FILE="$OUTPUT_DIR/RUN_START_TIME.txt"
END_FILE="$OUTPUT_DIR/RUN_END_TIME.txt"

# Check for timestamp files
if [ ! -f "$START_FILE" ] || [ ! -f "$END_FILE" ]; then
    echo "Error: No benchmark timestamps found."
    echo "Run 'make run-bench' first."
    exit 1
fi

START=$(cat "$START_FILE")
END=$(cat "$END_FILE")

# Auto-detect profile based on running containers
if docker compose ps --format '{{.Names}}' 2>/dev/null | grep -q dbz; then
    PROFILE="full"
    CONTAINERS="oracle,olr,dbz,kafka"
    TITLE="Full Pipeline Performance Test"
else
    PROFILE="olr-only"
    CONTAINERS="oracle,olr"
    TITLE="OLR-Only Performance Test"
fi

REPORT_DIR="reports/performance/$(date +%Y%m%d_%H%M)"
REPORT_FILE="$REPORT_DIR/charts.html"

echo "=========================================="
echo "Generating report for $PROFILE profile"
echo "  Start: $START"
echo "  End:   $END"
echo "  Output: $REPORT_FILE"
echo "=========================================="

python3 scripts/report-generator/generate_report.py \
    --start "$START" \
    --end "$END" \
    --containers "$CONTAINERS" \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'oracledb_dml_redo_entries' \
    --rate-of 'oracledb_dml_redo_bytes' \
    --total-of 'bytes_sent' \
    --title "$TITLE" \
    --output "$REPORT_FILE"

echo "=========================================="
echo "Report generated: $REPORT_FILE"
echo "=========================================="
