# Oracle CDC Test Project

## Project Structure

- `chart/` - Helm chart for Kubernetes deployment
- `docker-compose.yml` + `config/` - Docker Compose setup (mirrors Helm chart)

## Key Components

| Component | Image | Purpose |
|-----------|-------|---------|
| Oracle | `container-registry.oracle.com/database/free:23.5.0.0-lite` | Oracle 23ai Free (CDB: FREE, PDB: FREEPDB1) |
| Debezium | `quay.io/debezium/server:3.3.2.Final` | CDC via OLR adapter → Kafka |
| OpenLogReplicator | `rophy/openlogreplicator:1.8.7` | CDC via direct redo log parsing |
| Kafka | `apache/kafka:3.9.0` | Message broker for CDC events |
| kafka-consumer | `python:3.11-slim` | Consumes Kafka events, writes to file |
| HammerDB | `tpcorg/hammerdb:v4.10` | TPROC-C benchmark |

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

These are mounted to `/opt/oracle/scripts/startup/` which runs on every container start. The shell wrapper ensures setup only runs once.

**Why startup instead of setup?** Oracle's pre-built images with named volumes skip `/opt/oracle/scripts/setup/` because the DB appears "already created". See [oracle/docker-images#2644](https://github.com/oracle/docker-images/issues/2644).

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

**Note**: OLR requires read access to Oracle redo logs. The oracle-init container sets permissions on `/opt/oracle/fra`. For newly created archived logs, you may need to run:
```bash
docker compose exec oracle chmod -R o+r /opt/oracle/fra/FREE/archivelog
```

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

```bash
docker compose --profile hammerdb run --rm hammerdb build
```

### Step 5: Enable Supplemental Logging for TPCC Tables

```bash
docker compose exec -T oracle sqlplus -S / as sysdba < config/oracle/enable-tpcc-supplemental-logging.sql
```

### Step 6: Restart OLR and Debezium to Pick Up TPCC Tables

```bash
docker compose restart olr dbz
sleep 30

# Verify streaming resumed
docker compose logs dbz --tail=5 2>&1 | grep "Starting streaming"
docker compose logs olr --tail=5 2>&1 | grep -E "processing redo|ERROR"
```

### Step 7: Run HammerDB Workload

```bash
docker compose --profile hammerdb run --rm hammerdb run
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
