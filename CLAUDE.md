# Oracle CDC Test Project

## Project Structure

- `chart/` - Helm chart for Kubernetes deployment
- `docker-compose.yml` + `config/` - Docker Compose setup (mirrors Helm chart)

## Key Components

| Component | Image | Purpose |
|-----------|-------|---------|
| Oracle | `container-registry.oracle.com/database/free:23.5.0.0-lite` | Oracle 23ai Free (CDB: FREE, PDB: FREEPDB1) |
| Debezium | `quay.io/debezium/server:2.7` | CDC via LogMiner |
| File-writer | `python:3.11-slim` | HTTP sink for CDC events |
| HammerDB | `tpcorg/hammerdb:v4.10` | TPROC-C benchmark |

## Database Credentials

| User | Password | Scope | Purpose |
|------|----------|-------|---------|
| sys | OraclePwd123 | CDB | SYSDBA |
| c##dbzuser | dbzpwd | CDB | Debezium connector |
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

Config: `config/debezium/application.properties`

Capture filter includes both test and HammerDB schemas:
```properties
debezium.source.schema.include.list=USR1,TPCC
```

## Docker Compose Commands

```bash
# Start
docker compose up -d

# With HammerDB
docker compose --profile hammerdb up -d

# HammerDB operations
docker compose --profile hammerdb run --rm hammerdb build   # Create TPCC schema
docker compose --profile hammerdb run --rm hammerdb run     # Run workload
docker compose --profile hammerdb run --rm hammerdb delete  # Drop TPCC schema

# Clean restart
docker compose down -v && docker compose up -d
```

## Testing CDC

```bash
# Insert test row
docker exec oracle sqlplus -S USR1/USR1PWD@//localhost:1521/FREEPDB1 <<< "INSERT INTO ADAM1 VALUES (99, 'Test', 1, SYSTIMESTAMP); COMMIT;"

# Check captured events
docker exec file-writer tail -1 /app/output/events.json | jq
```

## Ports

| Service | Port |
|---------|------|
| Oracle | 1521 |
| Debezium | 8080 |
| File-writer | 8083 |
| JMX exporter | 9404 |
| Prometheus | 9090 |
