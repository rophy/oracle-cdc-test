# Oracle CDC Test Project

## Project Structure

- `chart/` - Helm chart for Kubernetes deployment
- `docker-compose.yml` + `config/` - Docker Compose setup (mirrors Helm chart)

## Key Components

| Component | Image | Purpose |
|-----------|-------|---------|
| Oracle | `gvenzl/oracle-free:23.9-slim-faststart` | Oracle 23ai Free (CDB: FREE, PDB: FREEPDB1) |
| Debezium | `debezium-server:patched` | CDC via OLR adapter → Kafka (patched for auto-commit fix) |
| OpenLogReplicator | `rophy/openlogreplicator:1.8.7` | CDC via direct redo log parsing |
| Kafka | `apache/kafka:3.9.0` | Message broker for CDC events |
| kafka-consumer | `python:3.11-slim` | Consumes Kafka events, writes to file |
| HammerDB | `tpcorg/hammerdb:v4.10` | TPROC-C benchmark |

**Note on Oracle image**: We use gvenzl instead of Oracle's official lite image because the lite image has broken `DBMS_METADATA` package (see `KNOWN_ISSUES.md`). The gvenzl slim-faststart variant properly handles XDB dependencies.

## Database Credentials

| User | Password | Scope | Purpose |
|------|----------|-------|---------|
| sys | OraclePwd123 | CDB | SYSDBA |
| c##dbzuser | dbzpwd | CDB | Debezium connector |
| c##olruser | olrpwd | CDB+PDB | OpenLogReplicator connector |
| USR1 | USR1PWD | FREEPDB1 | Test schema owner |
| TPCC | TPCCPWD | FREEPDB1 | HammerDB schema (created by HammerDB) |

## Oracle Setup Script

Scripts in `config/oracle/`:
- `01_startup.sh` - Wrapper with idempotency guard (checks `/opt/oracle/oradata/dbinit` marker)
- `setup.sql.template` - SQL setup (ARCHIVELOG, supplemental logging, users, test table)

These are mounted to `/container-entrypoint-startdb.d/` (gvenzl image) which runs on every container start. The shell wrapper ensures setup only runs once.

**Archive log configuration**: Archive logs are stored in `/opt/oracle/oradata/FREE/archivelog` (via `LOG_ARCHIVE_DEST_1`). This keeps both online redo logs and archived logs in the same shared volume, accessible to OLR.

**Note**: The SQL script does SHUTDOWN IMMEDIATE which causes race condition. Debezium has `restart: on-failure` to handle this.

## Debezium Configuration

Config: `config/debezium/application-olr.properties`

Uses Kafka sink with OLR adapter:
```properties
debezium.sink.type=kafka
debezium.sink.kafka.producer.bootstrap.servers=kafka:9092
debezium.source.database.connection.adapter=olr
debezium.source.schema.include.list=USR1,TPCC
```

## Docker Compose Commands

**IMPORTANT: ALWAYS use `docker compose` to manage containers. NEVER use `docker` commands directly (e.g., `docker exec`, `docker logs`, `docker rm`). Use `docker compose exec`, `docker compose logs`, etc. instead.**

```bash
# Start (Debezium CDC)
docker compose up -d

# With OpenLogReplicator (alternative CDC, ~7x faster than Debezium)
docker compose --profile olr up -d

# With HammerDB
docker compose --profile hammerdb up -d

# Combined: OLR + HammerDB
docker compose --profile olr --profile hammerdb up -d

# HammerDB operations
docker compose --profile hammerdb run --rm hammerdb build   # Create TPCC schema
docker compose --profile hammerdb run --rm hammerdb run     # Run workload
docker compose --profile hammerdb run --rm hammerdb delete  # Drop TPCC schema

# Clean restart
docker compose down -v && docker compose up -d
```

## OpenLogReplicator Configuration

Config: `config/openlogreplicator/OpenLogReplicator.json`

Key settings:
- `con-id: 3` - FREEPDB1 container ID (required for multitenant)
- `server: oracle:1521/FREEPDB1` - Connect to PDB for schema discovery
- Filter for USR1 and TPCC schemas

Output: `/output/events.json` (JSON format with before/after values)

**Note**: OLR requires read access to Oracle redo logs. The `oracle-init` container sets permissions on `/opt/oracle/oradata`. OLR uses `reader.type: "online"` which queries Oracle's `V$LOG` and `V$ARCHIVED_LOG` views to dynamically discover log file locations.

## Debezium with OpenLogReplicator Adapter

The `dbz` service uses Debezium with the OLR adapter instead of LogMiner.

Config: `config/debezium/application-olr.properties`

### OLR Format Configuration Caveat

The [Debezium documentation](https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-openlogreplicator-configuration) specifies OLR format as:
```json
"format": {
  "scn-all": 1,
  ...
}
```

However, OLR 1.8.7 does not support `scn-all`. Use these equivalent parameters instead:
```json
"format": {
  "scn": 0,
  "scn-type": 1,
  ...
}
```

Where:
- `"scn": 0` - Output SCN as numeric (not hex string), uses field name `scn` (not `scns`)
- `"scn-type": 1` - Include SCN in all payloads (ALL_PAYLOADS flag)

This achieves the same result as the documented `"scn-all": 1`.

## Testing CDC

```bash
# Insert test row
docker compose exec oracle sqlplus -S USR1/USR1PWD@//localhost:1521/FREEPDB1 <<< "INSERT INTO ADAM1 VALUES (99, 'Test', 1, SYSTIMESTAMP); COMMIT;"

# Check captured events (via kafka-consumer)
docker compose exec kafka-consumer tail -1 /app/output/events.json | jq

# List Kafka topics
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

# Check captured events (OpenLogReplicator direct output)
docker compose exec olr tail -1 /output/events.json | jq
```

## HammerDB Stress Test Procedure

To accurately measure Debezium CDC throughput, follow these steps in order. The key is to complete Debezium's initial snapshot **before** running the HammerDB workload.

**IMPORTANT**: When running HammerDB commands (build/run), execute them in background and continuously monitor container logs. Debezium may crash when encountering unknown tables - see `KNOWN_ISSUES.md` for details.

### Step 1: Start Base Stack (without HammerDB)

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
docker compose --profile hammerdb run --rm hammerdb build
docker compose start dbz

# Option B: Run in background and monitor (Debezium will crash-loop)
docker compose --profile hammerdb run --rm hammerdb build &
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
docker compose --profile hammerdb run --rm hammerdb run &

# Monitor in parallel (run these in separate terminals or check periodically):
docker compose logs -f dbz olr                              # Watch CDC logs
docker compose logs kafka-consumer --tail=10 | grep Throughput  # Check throughput
docker compose ps                                           # Check status
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

## Ports

| Service | Port |
|---------|------|
| Oracle | 1521 |
| Kafka | 9092 |
| Debezium | 8080 |
| JMX exporter | 9404 |
| Prometheus | 9090 |
| cAdvisor | 8080 |

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

#### 2. Kafka Consumer Throughput (events/sec)

```bash
# Extract throughput readings from kafka-consumer logs
docker compose logs kafka-consumer 2>&1 | grep -E "Throughput:" | \
  awk '{print $1, $NF}' | sed 's/events\/sec//'
```

#### 3. Total Events by Topic

```bash
# Query Prometheus for final topic offsets
docker compose exec -T prometheus wget -qO- \
  'http://localhost:9090/api/v1/query?query=kafka_topic_partition_current_offset' | jq -r '
  .data.result[] | "\(.metric.topic) \(.value[1])"' | sort
```

#### 4. OLR Throughput (events/sec)

```bash
# Query Prometheus for OLR processing rate
docker compose exec -T prometheus wget -qO- \
  'http://localhost:9090/api/v1/query_range?query=sum(rate(dml_ops{filter="out"}[30s]))&start=START_TIME&end=END_TIME&step=10s' | \
  jq -r '.data.result[0].values | .[] | "\(.[0]) \(.[1])"'
```

#### 5. Debezium → Kafka Throughput (events/sec)

```bash
# Query Prometheus for Kafka offset rate (Debezium output)
docker compose exec -T prometheus wget -qO- \
  'http://localhost:9090/api/v1/query_range?query=sum(rate(kafka_topic_partition_current_offset[30s]))&start=START_TIME&end=END_TIME&step=10s' | \
  jq -r '.data.result[0].values | .[] | "\(.[0]) \(.[1])"'
```

#### 6. Container Resource Usage

```bash
# Memory (MB)
docker compose exec -T prometheus wget -qO- \
  'http://localhost:9090/api/v1/query_range?query=container_memory_usage_bytes{name=~".*oracle.*|.*olr.*|.*dbz.*|.*kafka.*"}/1024/1024&start=START_TIME&end=END_TIME&step=10s' | jq

# CPU (%)
docker compose exec -T prometheus wget -qO- \
  'http://localhost:9090/api/v1/query_range?query=rate(container_cpu_usage_seconds_total{name=~".*oracle.*|.*olr.*|.*dbz.*|.*kafka.*"}[30s])*100&start=START_TIME&end=END_TIME&step=10s' | jq
```

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
