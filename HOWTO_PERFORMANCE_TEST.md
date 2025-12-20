# Performance Testing Guide

This guide covers how to run HammerDB stress tests and generate performance reports.

## Prerequisites

- Docker Compose stack running (`docker compose up -d`)
- Oracle database initialized (check for `/opt/oracle/oradata/dbinit` marker)

## HammerDB Stress Test Procedure

To accurately measure CDC throughput, follow these steps in order. The key is to complete the initial snapshot **before** running the HammerDB workload.

**IMPORTANT**: When running HammerDB commands (build/run), execute them in background and continuously monitor container logs. Debezium may crash when encountering unknown tables - see `KNOWN_ISSUES.md` for details.

### Step 1: Clean Up and Start Base Stack

```bash
docker compose down -v

# Clean up output files from previous runs (runs as root to handle permission issues)
docker compose --profile=clean run --rm clean

docker compose up -d
```

### Step 2: Wait for Oracle Setup to Complete

```bash
until docker compose exec oracle ls /opt/oracle/oradata/dbinit 2>/dev/null; do
  echo "Waiting for Oracle setup..."
  sleep 10
done
echo "Oracle setup complete"
```

### Step 3: Wait for Debezium to Complete Snapshot and Start Streaming

```bash
until docker compose logs dbz 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium snapshot..."
  sleep 10
done
echo "Debezium is streaming"
```

### Step 4: Build TPCC Schema

**Note**: Stop Debezium first to avoid crashes on unknown tables, or run build in background and monitor.

```bash
# Option A: Stop Debezium during build (recommended)
docker compose stop dbz
docker compose exec hammerdb /scripts/entrypoint.sh build
docker compose start dbz

# Option B: Run in background and monitor (Debezium will crash-loop)
docker compose exec hammerdb /scripts/entrypoint.sh build &
# Monitor in parallel:
docker compose logs -f dbz olr  # Watch for errors
docker compose ps               # Check container status
```

### Step 5: Enable Supplemental Logging for TPCC Tables

```bash
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql
```

### Step 6: Restart OLR and Debezium to Pick Up TPCC Tables

```bash
# Record timestamp before restart
RESTART_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

docker compose restart olr dbz

# Wait for Debezium to complete snapshot and start streaming
# This may take several minutes as it snapshots all TPCC tables (~4M records)
echo "Waiting for Debezium snapshot to complete (this may take 5-10 minutes)..."
until docker compose logs dbz --since="$RESTART_TIME" 2>&1 | grep -q "Starting streaming"; do
  echo "Still snapshotting... ($(date +%H:%M:%S))"
  sleep 30
done
echo "Debezium is now streaming"

# Verify OLR is processing
docker compose logs olr --tail=5 2>&1 | grep -E "processing redo|ERROR"
```

### Step 7: Run HammerDB Workload

Run in background and monitor CDC pipeline:

```bash
# Start workload in background
docker compose exec hammerdb /scripts/entrypoint.sh run &

# Monitor in parallel (run these in separate terminals or check periodically):
docker compose logs -f dbz olr                              # Watch CDC logs
docker compose logs kafka-consumer --tail=10 | grep Throughput  # Check throughput
docker compose ps                                           # Check status

# Check HammerDB output logs
ls -la output/hammerdb/
tail -f output/hammerdb/run_*.log
```

### Step 8: Monitor Throughput and Resources

```bash
# Kafka consumer throughput (reported every 10 seconds)
docker compose logs kafka-consumer --tail=10 | grep Throughput

# Total events captured
docker compose exec kafka-consumer wc -l /app/output/events.json

# Container resource usage
docker stats --no-stream | grep -E "oracle|dbz|olr|kafka"

# Prometheus metrics (if available)
curl -s "http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total"
```

### Why This Order Matters

| Step | Reason |
|------|--------|
| Start without HammerDB | Debezium snapshot requires stable DB connections; heavy load causes timeouts |
| Wait for streaming | Snapshot must complete before workload, otherwise Debezium retries indefinitely |
| Restart after TPCC | OLR and Debezium need to discover the new TPCC tables |

### Expected Results (4 VUs, 10 warehouses, 5 min duration)

| Metric | Value |
|--------|-------|
| Debezium Throughput | ~6,000 events/sec |
| Oracle Peak CPU | ~160% (of 200% Free limit) |
| OLR Memory | ~2 GiB |
| Debezium Memory | ~630 MiB |

## Performance Report Generation

After running a HammerDB stress test, generate a performance report using the report generator script.

### Prerequisites

```bash
pip install -r scripts/report-generator/requirements.txt
```

### Generate Report

```bash
# Note your test start and end times (UTC), then run:
python3 scripts/report-generator/generate_report.py \
    --start "2025-12-20T20:12:00Z" \
    --end "2025-12-20T20:22:00Z" \
    --containers oracle,olr \
    --rate-of 'dml_ops{filter="out"}' \
    --total-of 'bytes_sent' \
    --title "Performance Test - 60 VUs" \
    --output reports/performance/$(date +%Y%m%d_%H%M)/charts.html
```

The script queries Prometheus via `docker compose exec` and generates an HTML report with:
- Summary table (min/avg/max/total for each metric)
- CPU usage chart (per container)
- Memory usage chart (per container)
- Rate charts (events/sec over time)
- Total charts (raw counter values over time)

### CLI Options

| Option | Description | Example |
|--------|-------------|---------|
| `--start` | Test start time (ISO format) | `2025-12-20T20:12:00Z` |
| `--end` | Test end time (ISO format) | `2025-12-20T20:22:00Z` |
| `--containers` | Comma-separated container names | `oracle,olr,dbz` |
| `--rate-of` | Metric for rate chart (repeatable) | `dml_ops{filter="out"}` |
| `--total-of` | Metric for total chart (repeatable) | `bytes_sent` |
| `--title` | Report title | `"Performance Test - 60 VUs"` |
| `--output` | Output HTML file path | `reports/test/charts.html` |
| `--step` | Query step in seconds (default: 30) | `60` |

### Available Metrics

**OLR Metrics (use with `--rate-of` or `--total-of`):**

| Metric | Description |
|--------|-------------|
| `dml_ops{filter="out"}` | DML operations output (by table, type) |
| `dml_ops{filter="skip"}` | Skipped operations |
| `bytes_parsed` | Bytes of redo log parsed |
| `bytes_sent` | Bytes sent to output |
| `messages_sent` | Messages sent |
| `checkpoints` | Checkpoint operations |
| `log_switches` | Redo log switches |

**Label filters for `dml_ops`:**
- `filter`: `out`, `skip`, `partial`
- `type`: `insert`, `update`, `delete`, `commit`, `rollback`
- `table`: `CUSTOMER`, `ORDERS`, `STOCK`, etc.

### Example: Detailed Report

```bash
python3 scripts/report-generator/generate_report.py \
    --start "2025-12-20T20:12:00Z" \
    --end "2025-12-20T20:22:00Z" \
    --containers oracle,olr \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'dml_ops{filter="out",type="insert"}' \
    --rate-of 'dml_ops{filter="out",type="update"}' \
    --total-of 'bytes_sent' \
    --total-of 'bytes_parsed' \
    --title "Performance Test - Detailed" \
    --output reports/performance/detailed/charts.html
```

### Notes

- **Do NOT count events.json lines** for throughput - use Prometheus metrics instead
- **Oracle Free limits**: 2 cores (200% max CPU), 2 GB SGA
- **OLR processes in bursts**: Throughput spikes when redo logs are archived

## Getting HammerDB Job Metrics

See [HOWTO_HAMMERDB.md](HOWTO_HAMMERDB.md) for details on:
- Running HammerDB commands
- Accessing the HammerDB web service
- Retrieving job metrics via REST API
