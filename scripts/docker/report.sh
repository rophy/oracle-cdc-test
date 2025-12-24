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

echo "=========================================="
echo "Generating Performance Report"
echo "Start: $START_TIME"
echo "End:   $END_TIME"
echo "Output: $REPORT_DIR/report.html"
echo "=========================================="

python3 "$REPORT_GEN" \
    --start "$START_TIME" \
    --end "$END_TIME" \
    --containers "oracle,olr-dbz,dbz,kafka,kafka-consumer" \
    --output "$REPORT_DIR/report.html" \
    --title "Performance Test $(date +%Y-%m-%d)"

echo "=========================================="
echo "Report generated: $REPORT_DIR/report.html"
echo "=========================================="
