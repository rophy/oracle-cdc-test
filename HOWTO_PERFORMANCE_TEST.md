# Performance Testing Guide

This guide covers how to run HammerDB stress tests and generate performance reports.

## Prerequisites

- Docker Compose stack running (`docker compose up -d`)
- Oracle database initialized (check for `/opt/oracle/oradata/dbinit` marker)

## HammerDB Stress Test Procedure

To accurately measure CDC throughput, follow these steps in order. The key is to complete the initial snapshot **before** running the HammerDB workload.

**IMPORTANT**: When running HammerDB commands (build/run), execute them in background and continuously monitor container logs. Debezium may crash when encountering unknown tables - see `KNOWN_ISSUES.md` for details.

### Step 1: Start Base Stack

```bash
docker compose down -v
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

After running a HammerDB stress test, generate a performance report with time-series charts.

### Report Structure

```
reports/performance/YYYYMMDD_HHMM/
├── README.md      # Markdown summary with test config, results, key findings
└── charts.html    # Interactive Chart.js charts for time-series visualization
```

### Data Collection

#### 1. Test Configuration (for README.md)

```bash
# HammerDB settings (check hammerdb container or config)
# - Warehouses, Virtual Users, Rampup Time, Duration

# Infrastructure versions
docker compose images | grep -E "oracle|olr|dbz|kafka"
```

#### 2. Querying Prometheus for Time-Series Metrics

Use `curl` from the hammerdb container to query Prometheus. The hammerdb container has curl installed and can reach prometheus via Docker network.

**Setting the Time Range:**

```bash
# Convert your test start/end times to Unix timestamps
# Example: 2025-12-20 18:38:00 UTC
date -d "2025-12-20T18:38:00Z" +%s  # Returns: 1766255880

# Set environment variables for the time range
START_TS=1766255880  # Test start time (unix timestamp)
END_TS=1766256480    # Test end time (unix timestamp)
```

**URL Encoding Reference:**

PromQL queries must be URL-encoded when passed as query parameters:

| Character | URL Encoded |
|-----------|-------------|
| `{` | `%7B` |
| `}` | `%7D` |
| `[` | `%5B` |
| `]` | `%5D` |
| `=` | `%3D` |
| `"` | `%22` |
| `~` | `%7E` |
| `\|` | `%7C` |

#### 3. OLR DML Throughput (events/sec)

```bash
# PromQL: sum(rate(dml_ops{filter="out"}[30s]))
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(rate(dml_ops%7Bfilter%3D%22out%22%7D%5B30s%5D))&start=${START_TS}&end=${END_TS}&step=30"'
```

#### 4. Container CPU Usage (%)

```bash
# Oracle CPU
# PromQL: sum(rate(container_cpu_usage_seconds_total{name=~".*oracle.*"}[30s]))*100
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(rate(container_cpu_usage_seconds_total%7Bname%3D~%22.*oracle.*%22%7D%5B30s%5D))*100&start=${START_TS}&end=${END_TS}&step=30"'

# OLR CPU
# PromQL: sum(rate(container_cpu_usage_seconds_total{name=~".*olr.*"}[30s]))*100
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(rate(container_cpu_usage_seconds_total%7Bname%3D~%22.*olr.*%22%7D%5B30s%5D))*100&start=${START_TS}&end=${END_TS}&step=30"'
```

#### 5. Container Memory Usage (MB)

```bash
# Oracle Memory
# PromQL: sum(container_memory_usage_bytes{name=~".*oracle.*"})/1024/1024
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(container_memory_usage_bytes%7Bname%3D~%22.*oracle.*%22%7D)/1024/1024&start=${START_TS}&end=${END_TS}&step=30"'

# OLR Memory
# PromQL: sum(container_memory_usage_bytes{name=~".*olr.*"})/1024/1024
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(container_memory_usage_bytes%7Bname%3D~%22.*olr.*%22%7D)/1024/1024&start=${START_TS}&end=${END_TS}&step=30"'
```

#### 6. Current OLR DML Counts (Instant Query)

```bash
# Get current totals for all DML operations
# PromQL: dml_ops{filter="out"}
docker compose exec hammerdb curl -s 'http://prometheus:9090/api/v1/query?query=dml_ops'
```

#### 7. Parsing Prometheus Response

The response format is JSON with values as `[timestamp, value]` pairs:

```bash
# Extract values with jq
docker compose exec -e START_TS=1766255880 -e END_TS=1766256480 hammerdb bash -c \
  'curl -s "http://prometheus:9090/api/v1/query_range?query=sum(rate(dml_ops%7Bfilter%3D%22out%22%7D%5B30s%5D))&start=${START_TS}&end=${END_TS}&step=30"' | \
  jq -r '.data.result[0].values[] | "\(.[0]): \(.[1]) events/sec"'
```

#### 8. Available OLR Metrics

| Metric | Description |
|--------|-------------|
| `dml_ops{filter="out"}` | DML operations output (by table, type) |
| `dml_ops{filter="skip"}` | Skipped operations |
| `memory_used_mb` | OLR memory usage |
| `bytes_parsed` | Bytes of redo log parsed |
| `bytes_sent` | Bytes sent to output |
| `checkpoints` | Checkpoint operations |

#### 9. Available cAdvisor Metrics

| Metric | Description |
|--------|-------------|
| `container_cpu_usage_seconds_total` | Cumulative CPU usage |
| `container_memory_usage_bytes` | Current memory usage |
| `container_network_receive_bytes_total` | Network bytes received |
| `container_network_transmit_bytes_total` | Network bytes transmitted |

#### 10. Do NOT Count events.json Lines

**WARNING**: Do not use `wc -l` on OLR's `events.json` file to measure throughput:

```bash
# DON'T DO THIS
wc -l output/olr/events.json  # BAD - slow, misleading
```

Reasons:
- **Slow**: The file can grow to tens of GB; counting lines takes minutes
- **Misleading**: Includes buildschema initial data load (millions of rows), not just workload events
- **Inaccurate**: Line count doesn't equal DML operation count

**Instead**, always use Prometheus `dml_ops` metrics for accurate throughput measurement.

### Charts to Include (charts.html)

Use Chart.js for interactive visualization. Include these charts:

**Component Throughput (events/sec):**
1. **OpenLogReplicator** - `rate(dml_ops{filter="out"}[30s])` - Shows bursty redo log processing
2. **Debezium → Kafka** - `rate(kafka_topic_partition_current_offset[30s])` - Output to Kafka
3. **Kafka Consumer** - From kafka-consumer logs - End-to-end consumption
4. **Kafka Topics** - Line chart breakdown by topic (ORDER_LINE, STOCK, etc.)

**Resource Usage:**
5. **Container Memory** - Oracle, OLR, Debezium, Kafka (MB over time)
6. **Container CPU** - Oracle, OLR, Debezium, Kafka (% over time)

### Key Metrics for README.md

| Metric | Source |
|--------|--------|
| Total Events Captured | `sum(kafka_topic_partition_current_offset)` |
| Peak Throughput | Max from kafka-consumer logs |
| Average Throughput | Mean from kafka-consumer logs |
| OLR Peak Processing | Max from `rate(dml_ops[30s])` |
| OLR Memory Used | `memory_used_mb` metric |
| Test Duration | HammerDB rampup + duration |

### Example Prometheus Time Range

Replace `START_TIME` and `END_TIME` with ISO8601 timestamps:

```bash
START_TIME="2025-12-20T02:00:00Z"
END_TIME="2025-12-20T02:25:00Z"
```

### Notes on Data Interpretation

- **OLR processes in bursts**: OLR reads archived redo logs, so throughput spikes when logs are archived, then drops to 0 while waiting
- **Debezium buffers from OLR**: Debezium receives from OLR's network output and writes to Kafka at a more steady rate
- **Kafka Consumer lags slightly**: Consumer reads from Kafka with its own timing, showing end-to-end latency
- **Oracle Free limits**: 2 cores, 2 GB memory - CPU shown as % of available cores (200% max)

## Getting HammerDB Job Metrics

See [HOWTO_HAMMERDB.md](HOWTO_HAMMERDB.md) for details on:
- Running HammerDB commands
- Accessing the HammerDB web service
- Retrieving job metrics via REST API
