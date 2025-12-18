# Oracle CDC Test

A Helm chart for testing Oracle Change Data Capture (CDC) using Debezium Server with Oracle LogMiner.

## Overview

This project provides a complete testing environment for Oracle CDC, including:

- **Oracle Database 23ai Free** - Source database with archive logging enabled
- **Debezium Server** - CDC connector using Oracle LogMiner adapter
- **File Writer** - Simple HTTP sink that writes CDC events to files
- **HammerDB** - Optional TPROC-C benchmark client for performance testing
- **Prometheus Metrics** - JMX exporter sidecar for monitoring

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  Oracle 23ai    │────▶│  Debezium       │────▶│  File Writer    │
│  (LogMiner)     │     │  Server         │     │  (HTTP Sink)    │
│                 │     │                 │     │                 │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 │ JMX
                                 ▼
                        ┌─────────────────┐
                        │  JMX Exporter   │
                        │  (Prometheus)   │
                        └─────────────────┘
```

## Prerequisites

### Docker Compose
- Docker with Compose plugin
- At least 4 CPU cores and 8GB RAM available
- Access to Oracle Container Registry (for Oracle image)

### Kubernetes
- Kubernetes cluster (1.24+)
- Helm 3.x
- Storage class with dynamic provisioning (e.g., `ebs-gp3`)
- At least 4 CPU cores and 8GB RAM available

## Quick Start (Docker Compose)

### Start the Stack

```bash
# Start all services
docker compose up -d

# Watch logs until Oracle is ready
docker compose logs -f oracle

# Check all services are healthy
docker compose ps
```

### Verify CDC is Working

```bash
# Insert test row
docker exec oracle bash -c "sqlplus -S USR1/USR1PWD@//localhost:1521/FREEPDB1 << 'EOF'
INSERT INTO ADAM1 VALUES (99, 'Test', 1, SYSTIMESTAMP);
COMMIT;
EOF"

# Check captured events (wait ~15 seconds for LogMiner)
docker exec file-writer tail -1 /app/output/events.json | python3 -m json.tool
```

### Run HammerDB Stress Test

```bash
# Build TPCC schema (10 warehouses, takes ~3 minutes)
docker compose --profile hammerdb run --rm hammerdb build

# Run TPROC-C workload (2 min rampup + 5 min test)
docker compose --profile hammerdb run --rm hammerdb run

# Monitor CDC throughput during test
docker exec file-writer wc -l /app/output/events.json

# Check Debezium lag
curl -s "http://localhost:9090/api/v1/query?query=debezium_oracle_streaming_lag_ms" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Lag:', d['data']['result'][0]['value'][1], 'ms')"

# Delete TPCC schema (cleanup)
docker compose --profile hammerdb run --rm hammerdb delete
```

### View Prometheus Metrics

```bash
# Debezium metrics
curl -s http://localhost:9404/metrics | grep debezium_oracle

# Query via Prometheus
curl -s "http://localhost:9090/api/v1/query?query=debezium_oracle_streaming_total_captured_dml"
```

### Clean Up

```bash
# Stop and remove containers (keeps data)
docker compose down

# Full cleanup including volumes
docker compose down -v
```

## Performance Benchmarks

Tested with HammerDB TPROC-C (10 warehouses, 4 virtual users):

| Metric | Value |
|--------|-------|
| Debezium Throughput | **400-500 events/sec** |
| Peak Throughput | ~500 events/sec |
| Lag During Load | 10+ minutes |

**Note:** Debezium with LogMiner cannot keep up with high-throughput OLTP workloads. For higher throughput, consider Oracle GoldenGate with XStream adapter.

## Ports (Docker Compose)

| Service | Port |
|---------|------|
| Oracle | 1521 |
| Debezium | 8080 |
| File-writer | 8082 |
| JMX Exporter | 9404 |
| Prometheus | 9090 |

## Quick Start (Kubernetes)

### Install the Chart

```bash
# Clone the repository
cd oracle-cdc-test

# Install with default values
helm install debezium-cdc ./chart

# Or install with HammerDB enabled
helm install debezium-cdc ./chart --set hammerdb.enabled=true
```

### Wait for Oracle to Initialize

Oracle takes several minutes to initialize on first start:

```bash
# Watch Oracle logs until you see "DATABASE IS READY TO USE!"
kubectl logs -f deployment/debezium-cdc-oracle
```

### Verify CDC is Working

```bash
# Insert test data
kubectl exec -it deployment/debezium-cdc-oracle -- \
  sqlplus USR1/USR1PWD@FREEPDB1 <<EOF
INSERT INTO ADAM1 VALUES (1, 'Test', 100, SYSTIMESTAMP);
COMMIT;
EOF

# View captured CDC events
kubectl exec deployment/debezium-cdc-file-writer -- cat /app/output/events.json
```

## Configuration

### Oracle Database

| Parameter | Description | Default |
|-----------|-------------|---------|
| `oracle.image.tag` | Oracle image version | `23.5.0.0-lite` |
| `oracle.password` | SYS/SYSTEM password | `OraclePwd123` |
| `oracle.characterSet` | Database character set | `US7ASCII` |
| `oracle.persistence.oradata.size` | Data volume size | `30Gi` |
| `oracle.persistence.fra.size` | Flash Recovery Area size | `200Gi` |

### Debezium Server

| Parameter | Description | Default |
|-----------|-------------|---------|
| `debezium.image.tag` | Debezium Server version | `2.7` |
| `debezium.oracle.pdbName` | Pluggable database name | `FREEPDB1` |
| `debezium.schemaIncludeList` | Schemas to capture | `USR1` |
| `debezium.tableIncludeList` | Tables to capture | `USR1.ADAM.*` |
| `debezium.snapshotMode` | Snapshot mode | `initial` |

### HammerDB (Performance Testing)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `hammerdb.enabled` | Enable HammerDB | `false` |
| `hammerdb.tpcc.warehouses` | Number of warehouses | `10` |
| `hammerdb.tpcc.buildVirtualUsers` | VUs for schema build | `4` |
| `hammerdb.tpcc.runVirtualUsers` | VUs for workload | `4` |
| `hammerdb.tpcc.rampupMinutes` | Ramp-up time | `2` |
| `hammerdb.tpcc.durationMinutes` | Test duration | `5` |

### Prometheus Metrics

| Parameter | Description | Default |
|-----------|-------------|---------|
| `metrics.serviceMonitor.enabled` | Enable ServiceMonitor CR | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `15s` |

## Usage

### Connecting to Oracle

```bash
# As SYSDBA
kubectl exec -it deployment/debezium-cdc-oracle -- \
  sqlplus sys/OraclePwd123@FREEPDB1 as sysdba

# As application user
kubectl exec -it deployment/debezium-cdc-oracle -- \
  sqlplus USR1/USR1PWD@FREEPDB1
```

### Viewing Debezium Logs

```bash
kubectl logs -f deployment/debezium-cdc-debezium -c debezium
```

### Viewing CDC Events

```bash
# All events
kubectl exec deployment/debezium-cdc-file-writer -- cat /app/output/events.json

# Follow new events
kubectl exec deployment/debezium-cdc-file-writer -- tail -f /app/output/events.json
```

### Prometheus Metrics

Debezium metrics are exposed via JMX exporter on port 9404:

```bash
# Port-forward to access metrics
kubectl port-forward svc/debezium-cdc-debezium 9404:9404

# View metrics
curl http://localhost:9404/metrics | grep debezium_oracle
```

Key metrics:
- `debezium_oracle_streaming_total_captured_dml` - Total DML operations captured
- `debezium_oracle_streaming_lag_ms` - Lag from source in milliseconds
- `debezium_oracle_streaming_commit_throughput` - Commits per second
- `debezium_oracle_streaming_current_scn` - Current System Change Number

### HammerDB Performance Testing

Enable HammerDB for TPROC-C benchmarking:

```bash
# Enable HammerDB
helm upgrade debezium-cdc ./chart --set hammerdb.enabled=true

# Build TPROC-C schema (creates tables and loads data)
kubectl exec -it deployment/debezium-cdc-hammerdb -- bash -c \
  "cd /home/HammerDB-* && ./hammerdbcli auto /scripts/buildschema.tcl"

# Run TPROC-C workload
kubectl exec -it deployment/debezium-cdc-hammerdb -- bash -c \
  "cd /home/HammerDB-* && ./hammerdbcli auto /scripts/runworkload.tcl"

# Delete TPROC-C schema (cleanup)
kubectl exec -it deployment/debezium-cdc-hammerdb -- bash -c \
  "cd /home/HammerDB-* && ./hammerdbcli auto /scripts/deleteschema.tcl"
```

## Database Schema

The chart automatically creates the following in Oracle:

### Container Database (CDB)
- `c##dbzuser` - Debezium user with LogMiner privileges

### Pluggable Database (FREEPDB1)
- `USR1` schema with test table `ADAM1`
- `TPCC` schema (when HammerDB builds it) with TPROC-C tables

### Test Table Structure (ADAM1)

```sql
CREATE TABLE USR1.ADAM1 (
  ID NUMBER PRIMARY KEY,
  NAME VARCHAR2(100),
  VALUE NUMBER,
  CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

## Uninstalling

```bash
# Delete the Helm release
helm uninstall debezium-cdc

# Delete PVCs (this deletes the EBS volumes)
kubectl delete pvc -l app.kubernetes.io/instance=debezium-cdc
```

## Troubleshooting

### Oracle Not Starting

Check if the data volume has enough space:
```bash
kubectl describe pvc debezium-cdc-oracle-oradata
kubectl describe pvc debezium-cdc-oracle-fra
```

### Debezium Connection Errors

Verify Oracle is ready and the Debezium user exists:
```bash
kubectl exec -it deployment/debezium-cdc-oracle -- \
  sqlplus sys/OraclePwd123@FREE as sysdba <<EOF
SELECT username FROM dba_users WHERE username = 'C##DBZUSER';
EOF
```

### No CDC Events Captured

1. Check Debezium logs for errors:
   ```bash
   kubectl logs deployment/debezium-cdc-debezium -c debezium
   ```

2. Verify archive logging is enabled:
   ```bash
   kubectl exec -it deployment/debezium-cdc-oracle -- \
     sqlplus sys/OraclePwd123@FREE as sysdba <<EOF
   SELECT log_mode FROM v\$database;
   EOF
   ```

3. Check LogMiner is working:
   ```bash
   kubectl exec -it deployment/debezium-cdc-oracle -- \
     sqlplus sys/OraclePwd123@FREE as sysdba <<EOF
   SELECT * FROM v\$logmnr_contents WHERE ROWNUM < 10;
   EOF
   ```

### HammerDB Oracle Library Not Found

Ensure the pod has restarted after Helm upgrade to pick up LD_LIBRARY_PATH:
```bash
kubectl rollout restart deployment/debezium-cdc-hammerdb
```

## References

- [Debezium Oracle Connector](https://debezium.io/documentation/reference/stable/connectors/oracle.html)
- [Oracle LogMiner](https://docs.oracle.com/en/database/oracle/oracle-database/23/sutil/oracle-logminer-utility.html)
- [HammerDB Documentation](https://www.hammerdb.com/docs/)
- [Prometheus JMX Exporter](https://github.com/prometheus/jmx_exporter)
