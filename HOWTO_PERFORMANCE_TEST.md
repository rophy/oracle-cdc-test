# Performance Testing Guide

This guide covers how to run HammerDB stress tests and generate performance reports.

## Deployment Options

| Platform | Description |
|----------|-------------|
| **Docker Compose** | Local development, quick testing |
| **Kubernetes** | Production-like environment, uses Helm chart |

---

# Docker Compose

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make up` | Start base stack (Oracle + monitoring) |
| `make up-olr` | Start with OLR direct to file |
| `make up-full` | Start full pipeline (OLR → Debezium → Kafka) |
| `make down` | Stop all containers (preserves volumes) |
| `make clean` | Clean output files and remove everything including volumes |
| `make run-bench` | Run HammerDB benchmark with timestamp tracking |
| `make report` | Generate performance report from last benchmark run |

## Part 1: Setup (Common Steps)

These steps are the same regardless of which CDC profile you choose.

### Step 1.1: Clean Up Previous Run

```bash
make clean
```

### Step 1.2: Start the Stack

Choose your CDC profile:

| Profile | Command | Description |
|---------|---------|-------------|
| `olr-only` | `make up-olr` | OLR writes directly to file (lightweight) |
| `full` | `make up-full` | Full pipeline: OLR → Debezium → Kafka |

### Step 1.3: Wait for Oracle Setup to Complete

```bash
until docker compose exec oracle ls /opt/oracle/oradata/dbinit 2>/dev/null; do
  echo "Waiting for Oracle setup..."
  sleep 10
done
echo "Oracle setup complete"
```

### Step 1.4: Build TPCC Schema

See profile-specific instructions below for handling this step.

### Step 1.5: Enable Supplemental Logging for TPCC Tables

```bash
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql
```

---

## Part 2: Running the Test (Profile-Specific)

### Option A: OLR-Only Profile

The `olr-only` profile is simpler - OLR writes CDC events directly to `./output/olr/events.json`.

#### Step 2A.1: Build TPCC Schema

```bash
docker compose exec hammerdb /scripts/entrypoint.sh build
```

#### Step 2A.2: Restart OLR to Pick Up TPCC Tables

```bash
docker compose restart olr-file
```

#### Step 2A.3: Run HammerDB Workload

**Run the benchmark in background to allow parallel monitoring:**

```bash
make run-bench &
```

This script automatically:
- Records start/end timestamps to `output/hammerdb/RUN_START_TIME.txt` and `RUN_END_TIME.txt`
- Creates a timestamped log file `output/hammerdb/RUN_LOG_<timestamp>.txt`
- Pipes HammerDB output to both console and log file

**Monitor in parallel:**

```bash
docker compose logs -f olr-file              # Watch OLR logs
tail -f ./output/olr/events.json             # Watch CDC events
tail -f output/hammerdb/RUN_LOG_*.txt        # Watch HammerDB output
docker stats --no-stream | grep -E "oracle|olr"  # Resource usage
```

---

### Option B: Full Profile (OLR → Debezium → Kafka)

The `full` profile requires additional steps to handle Debezium snapshots.

**IMPORTANT**: When running HammerDB commands (build/run), execute them in background and continuously monitor container logs. Debezium may crash when encountering unknown tables - see `KNOWN_ISSUES.md` for details.

#### Step 2B.1: Wait for Debezium to Complete Initial Snapshot

```bash
until docker compose logs dbz 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium snapshot..."
  sleep 10
done
echo "Debezium is streaming"
```

#### Step 2B.2: Build TPCC Schema

**Note**: Stop Debezium first to avoid crashes on unknown tables, or run build in background and monitor.

```bash
# Option A: Stop Debezium during build (recommended)
docker compose stop dbz
docker compose exec hammerdb /scripts/entrypoint.sh build
docker compose start dbz

# Option B: Run in background and monitor (Debezium will crash-loop)
docker compose exec hammerdb /scripts/entrypoint.sh build &
# Monitor in parallel:
docker compose logs -f dbz olr-dbz  # Watch for errors
docker compose ps                   # Check container status
```

#### Step 2B.3: Restart OLR and Debezium to Pick Up TPCC Tables

```bash
# Record timestamp before restart
RESTART_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

docker compose restart olr-dbz dbz

# Wait for Debezium to complete snapshot and start streaming
# This may take several minutes as it snapshots all TPCC tables (~4M records)
echo "Waiting for Debezium snapshot to complete (this may take 5-10 minutes)..."
until docker compose logs dbz --since="$RESTART_TIME" 2>&1 | grep -q "Starting streaming"; do
  echo "Still snapshotting... ($(date +%H:%M:%S))"
  sleep 30
done
echo "Debezium is now streaming"

# Verify OLR is processing
docker compose logs olr-dbz --tail=5 2>&1 | grep -E "processing redo|ERROR"
```

#### Step 2B.4: Run HammerDB Workload

**Run the benchmark in background to allow parallel monitoring:**

```bash
make run-bench &
```

This script automatically:
- Records start/end timestamps to `output/hammerdb/RUN_START_TIME.txt` and `RUN_END_TIME.txt`
- Creates a timestamped log file `output/hammerdb/RUN_LOG_<timestamp>.txt`
- Pipes HammerDB output to both console and log file

**Monitor in parallel:**

```bash
docker compose logs -f dbz olr-dbz                              # Watch CDC logs
docker compose logs kafka-consumer --tail=10 | grep Throughput  # Check throughput
docker compose ps                                               # Check status
tail -f output/hammerdb/RUN_LOG_*.txt                           # Watch HammerDB output
```

#### Why This Order Matters (Full Profile)

| Step | Reason |
|------|--------|
| Start without HammerDB | Debezium snapshot requires stable DB connections; heavy load causes timeouts |
| Wait for streaming | Snapshot must complete before workload, otherwise Debezium retries indefinitely |
| Restart after TPCC | OLR and Debezium need to discover the new TPCC tables |

---

## Part 3: Collecting Metrics (Profile-Specific)

### Monitoring During Test

#### OLR-Only Profile

```bash
# OLR output (events written directly to file)
tail -f ./output/olr/events.json

# OLR logs
docker compose logs -f olr-file

# Container resource usage
docker stats --no-stream | grep -E "oracle|olr"
```

#### Full Profile

```bash
# Kafka consumer throughput (reported every 10 seconds)
docker compose logs kafka-consumer --tail=10 | grep Throughput

# Total events captured
docker compose exec kafka-consumer wc -l /app/output/events.json

# Container resource usage
docker stats --no-stream | grep -E "oracle|dbz|olr-dbz|kafka"

# Prometheus metrics (if available)
curl -s "http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total"
```

---

### Generating Performance Reports

After running a HammerDB stress test with `make run-bench`, generate a performance report:

```bash
make report
```

This automatically:
- Reads timestamps from `output/hammerdb/RUN_START_TIME.txt` and `RUN_END_TIME.txt`
- Detects the active profile (olr-only or full) and selects appropriate containers
- Generates an HTML report in `reports/performance/<timestamp>/charts.html`

#### Prerequisites

```bash
pip install -r scripts/report-generator/requirements.txt
```

#### Manual Report Generation

For custom time ranges or options, use the script directly:

```bash
python3 scripts/report-generator/generate_report.py \
    --start "2025-12-20T20:12:00Z" \
    --end "2025-12-20T20:22:00Z" \
    --containers oracle,olr,dbz,kafka \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'oracledb_dml_redo_entries' \
    --rate-of 'oracledb_dml_redo_bytes' \
    --total-of 'bytes_sent' \
    --title "Custom Performance Test" \
    --output reports/performance/$(date +%Y%m%d_%H%M)/charts.html
```

---

# Kubernetes (Helm Chart)

## Prerequisites

- Kubernetes cluster with kubectl configured
- Helm 3.x installed
- Storage class available for PVCs (e.g., `ebs-gp3` on AWS)

## Part 1: Deploy the Stack

### Step 1.1: Install the Helm Chart

```bash
# Update dependencies
helm dependency update chart/

# Install with full profile (default)
helm install oracle-cdc chart/ --create-namespace --namespace oracle-cdc

# Or install with olr-only profile
helm install oracle-cdc chart/ --create-namespace --namespace oracle-cdc --set mode=olr-only
```

### Step 1.2: Wait for All Pods to be Ready

```bash
kubectl get pods -n oracle-cdc -w
```

Wait until all pods show `Running` status and are ready (1/1 or 2/2).

### Step 1.3: Wait for Oracle Setup to Complete

```bash
until kubectl exec -n oracle-cdc deployment/oracle-cdc-oracle -- ls /opt/oracle/oradata/dbinit 2>/dev/null; do
  echo "Waiting for Oracle setup..."
  sleep 10
done
echo "Oracle setup complete"
```

### Step 1.4: Wait for Debezium Initial Snapshot (Full Profile Only)

```bash
until kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium snapshot..."
  sleep 10
done
echo "Debezium is streaming"
```

---

## Part 2: Build TPCC Schema and Run Benchmark

### Step 2.1: Build TPCC Schema

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-hammerdb -- /scripts/entrypoint.sh build
```

### Step 2.2: Enable Supplemental Logging for TPCC Tables

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-oracle -- sqlplus -S / as sysdba <<'EOF'
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
```

### Step 2.3: Restart OLR and Debezium to Pick Up TPCC Tables

```bash
kubectl rollout restart deployment/oracle-cdc-olr deployment/oracle-cdc-debezium -n oracle-cdc
kubectl rollout status deployment/oracle-cdc-olr -n oracle-cdc --timeout=120s
kubectl rollout status deployment/oracle-cdc-debezium -n oracle-cdc --timeout=120s
```

### Step 2.4: Wait for Debezium to Start Streaming Again

```bash
until kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium..."
  sleep 10
done
echo "Debezium is streaming"
```

### Step 2.5: Run HammerDB Benchmark

```bash
# Record start time
mkdir -p output/hammerdb
date -u +%Y-%m-%dT%H:%M:%SZ > output/hammerdb/RUN_START_TIME.txt

# Run benchmark
kubectl exec -n oracle-cdc deployment/oracle-cdc-hammerdb -- /scripts/entrypoint.sh run

# Record end time
date -u +%Y-%m-%dT%H:%M:%SZ > output/hammerdb/RUN_END_TIME.txt
```

---

## Part 3: Monitoring (Kubernetes)

### Check Pod Status

```bash
kubectl get pods -n oracle-cdc
```

### View Logs

```bash
# Oracle logs
kubectl logs -n oracle-cdc deployment/oracle-cdc-oracle -f

# OLR logs
kubectl logs -n oracle-cdc deployment/oracle-cdc-olr -f

# Debezium logs
kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium -f

# Kafka consumer logs
kubectl logs -n oracle-cdc deployment/oracle-cdc-kafka-consumer -f
```

### Check CDC Events Captured

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-kafka-consumer -- wc -l /app/output/events.json
```

### Check OLR Metrics

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-hammerdb -- \
  curl -s http://oracle-cdc-olr:9161/metrics | grep -E "dml_ops|bytes_sent"
```

---

## Part 4: Generate Performance Report (Kubernetes)

### Prerequisites

```bash
pip install -r scripts/report-generator/requirements.txt
```

### Generate Report

Use the `--k8s` flag to query Prometheus via kubectl:

```bash
START=$(cat output/hammerdb/RUN_START_TIME.txt)
END=$(cat output/hammerdb/RUN_END_TIME.txt)
REPORT_DIR="reports/performance/$(date +%Y%m%d_%H%M)"

python3 scripts/report-generator/generate_report.py \
    --start "$START" \
    --end "$END" \
    --containers oracle,olr,debezium,kafka \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'oracledb_dml_redo_entries' \
    --rate-of 'oracledb_dml_redo_bytes' \
    --total-of 'bytes_sent' \
    --title "Full Pipeline Performance Test (K8s)" \
    --output "$REPORT_DIR/charts.html" \
    --k8s
```

### Kubernetes-Specific CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `--k8s` | Enable Kubernetes mode (use kubectl) | `false` |
| `--k8s-namespace` | Kubernetes namespace | `oracle-cdc` |
| `--k8s-deployment` | Deployment to exec into for queries | `oracle-cdc-hammerdb` |

---

## Part 5: Cleanup (Kubernetes)

```bash
# Uninstall the Helm release
helm uninstall oracle-cdc -n oracle-cdc

# Delete the namespace (removes PVCs)
kubectl delete namespace oracle-cdc
```

---

# Report Generator CLI Options

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
| `--k8s` | Use kubectl instead of docker compose | - |
| `--k8s-namespace` | Kubernetes namespace | `oracle-cdc` |
| `--k8s-deployment` | Deployment for kubectl exec | `oracle-cdc-hammerdb` |

The script queries Prometheus and generates an HTML report with:
- Summary table (min/avg/max/total for each metric)
- CPU usage chart (per container)
- Memory usage chart (per container)
- Rate charts (events/sec over time)
- Total charts (raw counter values over time)

---

# Reference: Available Metrics

## OLR Metrics

Use with `--rate-of` or `--total-of`:

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

## Oracle Exporter Metrics

| Metric | Description |
|--------|-------------|
| `oracledb_dml_redo_entries` | Redo log entries (counter, correlates with DML ops) |
| `oracledb_dml_redo_bytes` | Total redo data generated (counter, bytes) |
| `oracledb_dml_block_changes` | Database block modifications (counter) |
| `oracledb_dml_rows_scanned` | Rows read by table scans (counter) |
| `oracledb_activity_user_commits` | Commit count (counter) |
| `oracledb_activity_execute_count` | SQL executions (counter) |
| `oracledb_wait_time_*` | Wait time by class (user_io, commit, concurrency, etc.) |

**Example Prometheus queries:**
```bash
# Redo entries per second (proxy for DML rate)
rate(oracledb_dml_redo_entries[1m])

# Redo throughput in KB/sec
rate(oracledb_dml_redo_bytes[1m]) / 1024

# Commits per second
rate(oracledb_activity_user_commits[1m])
```

---

# Expected Results

## OLR-Only (4 VUs, 10 warehouses, 5 min duration)

| Metric | Value |
|--------|-------|
| Oracle Peak CPU | ~160% (of 200% Free limit) |
| OLR Memory | ~2 GiB |

## Full Profile (4 VUs, 10 warehouses, 5 min duration)

| Metric | Value |
|--------|-------|
| Debezium Throughput | ~6,000 events/sec |
| Oracle Peak CPU | ~160% (of 200% Free limit) |
| OLR Memory | ~2 GiB |
| Debezium Memory | ~630 MiB |

---

# Notes

- **Do NOT count events.json lines** for throughput - use Prometheus metrics instead
- **Oracle Free limits**: 2 cores (200% max CPU), 2 GB SGA
- **OLR processes in bursts**: Throughput spikes when redo logs are archived

# See Also

- [HOWTO_HAMMERDB.md](HOWTO_HAMMERDB.md) - HammerDB commands, web service, REST API
