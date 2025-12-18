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

`config/oracle/01_setup.sql` runs on first container start:
- Enables ARCHIVELOG mode (requires SHUTDOWN/STARTUP)
- Enables supplemental logging
- Creates `c##dbzuser` with LogMiner privileges
- Creates `USR1.ADAM1` test table

**Note**: Script does SHUTDOWN IMMEDIATE which causes race condition. Debezium has `restart: on-failure` to handle this.

## Debezium Configuration

Config: `config/debezium/application.properties`

Current capture filter:
```properties
debezium.source.schema.include.list=USR1
debezium.source.table.include.list=USR1.ADAM.*
```

To capture TPCC tables from HammerDB, add `TPCC` schema.

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
| File-writer | 8081 |
| JMX exporter | 9404 |
| Prometheus | 9090 |
