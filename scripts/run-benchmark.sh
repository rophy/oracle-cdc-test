#!/bin/bash
#
# Run HammerDB benchmark with timestamp tracking for report generation.
#
# Outputs:
#   - output/hammerdb/RUN_START_TIME.txt  - Start timestamp (ISO 8601)
#   - output/hammerdb/RUN_END_TIME.txt    - End timestamp (ISO 8601)
#   - output/hammerdb/RUN_LOG_<timestamp>.txt - HammerDB output log
#

set -e

OUTPUT_DIR="output/hammerdb"
mkdir -p "$OUTPUT_DIR"

# Generate timestamps
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$OUTPUT_DIR/RUN_LOG_${LOG_TIMESTAMP}.txt"

# Save and display start time
echo "$START_TIME" > "$OUTPUT_DIR/RUN_START_TIME.txt"
echo "=========================================="
echo "Benchmark Start Time: $START_TIME"
echo "Log File: $LOG_FILE"
echo "=========================================="

# Run HammerDB, piping output to log file (and stdout)
docker compose exec -T hammerdb /scripts/entrypoint.sh run 2>&1 | tee "$LOG_FILE"

# Save and display end time
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$END_TIME" > "$OUTPUT_DIR/RUN_END_TIME.txt"

echo "=========================================="
echo "Benchmark End Time: $END_TIME"
echo "Duration: $START_TIME -> $END_TIME"
echo ""
echo "To generate report:"
echo "  make report"
echo "=========================================="
