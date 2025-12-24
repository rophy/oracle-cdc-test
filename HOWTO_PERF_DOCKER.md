# Performance Testing - Docker Compose

```bash
export DEPLOY_MODE=docker
```

## Part 1: Setup

### Step 1.1: Clean Up Previous Run

```bash
make clean
```

### Step 1.2: Start the Stack

Choose your CDC profile:

| Profile | Command | Description |
|---------|---------|-------------|
| `olr-only` | `make up-olr` | OLR writes directly to file (lightweight) |
| `full` | `make up-full` | Full pipeline: OLR -> Debezium -> Kafka |

### Step 1.3: Wait for Oracle Setup to Complete

```bash
until docker compose exec oracle ls /opt/oracle/oradata/dbinit 2>/dev/null; do
  echo "Waiting for Oracle setup..."
  sleep 10
done
echo "Oracle setup complete"
```

### Step 1.4: Build TPCC Schema

See profile-specific instructions below.

### Step 1.5: Enable Supplemental Logging for TPCC Tables

```bash
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql
```

---

## Part 2: OLR-Only Profile

The `olr-only` profile is simpler - OLR writes CDC events directly to `./output/olr/events.json`.

### Step 2.1: Build TPCC Schema

```bash
docker compose exec hammerdb /scripts/entrypoint.sh build
```

### Step 2.2: Restart OLR to Pick Up TPCC Tables

```bash
docker compose restart olr-file
```

### Step 2.3: Run HammerDB Workload

```bash
make run-bench &
```

This script automatically:
- Records start/end timestamps to `output/hammerdb/RUN_START_TIME.txt` and `RUN_END_TIME.txt`
- Creates a timestamped log file `output/hammerdb/RUN_LOG_<timestamp>.txt`

**Monitor in parallel:**

```bash
docker compose logs -f olr-file              # Watch OLR logs
tail -f ./output/olr/events.json             # Watch CDC events
tail -f output/hammerdb/RUN_LOG_*.txt        # Watch HammerDB output
docker stats --no-stream | grep -E "oracle|olr"  # Resource usage
```

---

## Part 2: Full Profile (OLR -> Debezium -> Kafka)

The `full` profile requires additional steps to handle Debezium snapshots.

**IMPORTANT**: Debezium may crash when encountering unknown tables - see `KNOWN_ISSUES.md` for details.

### Step 2.1: Wait for Debezium to Complete Initial Snapshot

```bash
until docker compose logs dbz 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium snapshot..."
  sleep 10
done
echo "Debezium is streaming"
```

### Step 2.2: Build TPCC Schema

Stop Debezium first to avoid crashes on unknown tables:

```bash
docker compose stop dbz
docker compose exec hammerdb /scripts/entrypoint.sh build
docker compose start dbz
```

### Step 2.3: Restart OLR and Debezium to Pick Up TPCC Tables

```bash
RESTART_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

docker compose restart olr-dbz dbz

# Wait for Debezium to complete snapshot (may take 5-10 minutes)
echo "Waiting for Debezium snapshot to complete..."
until docker compose logs dbz --since="$RESTART_TIME" 2>&1 | grep -q "Starting streaming"; do
  echo "Still snapshotting... ($(date +%H:%M:%S))"
  sleep 30
done
echo "Debezium is now streaming"
```

### Step 2.4: Run HammerDB Workload

```bash
make run-bench &
```

**Monitor in parallel:**

```bash
docker compose logs -f dbz olr-dbz                              # Watch CDC logs
docker compose logs kafka-consumer --tail=10 | grep Throughput  # Check throughput
docker compose ps                                               # Check status
tail -f output/hammerdb/RUN_LOG_*.txt                           # Watch HammerDB output
```

### Why This Order Matters

| Step | Reason |
|------|--------|
| Start without HammerDB | Debezium snapshot requires stable DB connections |
| Wait for streaming | Snapshot must complete before workload |
| Restart after TPCC | OLR and Debezium need to discover new TPCC tables |

---

## Part 3: Monitoring

### OLR-Only Profile

```bash
tail -f ./output/olr/events.json                    # CDC events
docker compose logs -f olr-file                     # OLR logs
docker stats --no-stream | grep -E "oracle|olr"    # Resource usage
```

### Full Profile

```bash
docker compose logs kafka-consumer --tail=10 | grep Throughput  # Throughput
docker compose exec kafka-consumer wc -l /app/output/events.json  # Total events
docker stats --no-stream | grep -E "oracle|dbz|olr-dbz|kafka"   # Resource usage
```

---

## Part 4: Generate Report

```bash
make report
```

This automatically:
- Reads timestamps from `output/hammerdb/`
- Detects the active profile and selects appropriate containers
- Generates an HTML report in `reports/performance/<timestamp>/report.html`

### Prerequisites

```bash
pip install -r scripts/report-generator/requirements.txt
```

### Manual Report Generation

```bash
python3 scripts/report-generator/generate_report.py \
    --start "2025-12-20T20:12:00Z" \
    --end "2025-12-20T20:22:00Z" \
    --containers oracle,olr-file \
    --rate-of 'dml_ops{filter="out"}' \
    --rate-of 'oracledb_dml_redo_entries' \
    --total-of 'bytes_sent' \
    --title "Custom Performance Test" \
    --output reports/performance/$(date +%Y%m%d_%H%M)/report.html
```

### Report Generator Options

| Option | Description | Example |
|--------|-------------|---------|
| `--start` | Test start time (ISO format) | `2025-12-20T20:12:00Z` |
| `--end` | Test end time (ISO format) | `2025-12-20T20:22:00Z` |
| `--containers` | Comma-separated container names | `oracle,olr-file` |
| `--rate-of` | Metric for rate chart (repeatable) | `dml_ops{filter="out"}` |
| `--total-of` | Metric for total chart (repeatable) | `bytes_sent` |
| `--title` | Report title | `"Performance Test"` |
| `--output` | Output HTML file path | `reports/test/report.html` |
| `--step` | Query step in seconds (default: 30) | `60` |

---

## Part 5: Cleanup

```bash
make down   # Stop containers (preserves volumes)
make clean  # Remove everything including volumes
```
