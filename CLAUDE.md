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
| HammerDB | `rophy/hammerdb:v4.10-20251227-r1` | TPROC-C benchmark |

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

## Docker Compose Profiles

The stack uses profiles to support different CDC architectures:

| Profile | Description | Services |
|---------|-------------|----------|
| (none) | Base stack only | oracle, prometheus, cadvisor, oracle-exporter, hammerdb |
| `olr-only` | OLR writes directly to file | + olr-file |
| `full` | Full CDC pipeline | + olr-dbz, kafka, kafka-consumer, dbz, jmx-exporter, kafka-exporter |
| `clean` | Cleanup utility | clean (manual run) |

## Makefile Commands

Use `make` targets instead of raw docker/kubectl commands:

```bash
export DEPLOY_MODE=docker  # or k8s
export PROFILE=full        # or olr-only

make clean      # Remove previous run
make up         # Start stack
make build      # Build TPCC schema and configure CDC
make run-bench  # Run benchmark
make report     # Generate report
```

**HammerDB output**: Logs are saved to `./output/hammerdb/` with timestamped filenames.

**Note**: Use `docker compose` (not `docker`) for any manual container operations.

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

# Check captured events (olr-only profile)
docker compose exec olr-file tail -1 /olr/output/events.json | jq

# Check captured events (full profile - via kafka-consumer)
docker compose exec kafka-consumer tail -1 /app/output/events.json | jq

# List Kafka topics (full profile)
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## Ports

| Service | Port |
|---------|------|
| Oracle | 1521 |
| Kafka | 9092 |
| Debezium | 8080 |
| JMX exporter | 9404 |
| Prometheus | 9090 |
| cAdvisor | 8080 |

## How-To Guides

For detailed procedures, see:
- `HOWTO_HAMMERDB.md` - HammerDB commands, web service, REST API
- `HOWTO_PERF.md` - Performance testing and metrics reference
