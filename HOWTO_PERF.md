# Performance Testing

## Quick Start

```bash
export DEPLOY_MODE=docker  # or k8s
export PROFILE=full        # or olr-only

make clean      # Remove previous run
make up         # Start stack
make build      # Build TPCC schema and configure CDC (~2-3 min)
make run-bench  # Run benchmark (~9 min: 2 rampup + 5 test + teardown)
make report     # Generate report
```

> **Note**: `make build` and `make run-bench` are long-running jobs. Run them in one terminal while monitoring logs in another to catch any issues early.

## Environment Variables

| Variable | Values | Required | Description |
|----------|--------|----------|-------------|
| `DEPLOY_MODE` | `docker`, `k8s` | Yes | Deployment platform |
| `PROFILE` | `full`, `olr-only` | Yes | CDC pipeline mode |
| `K8S_NAMESPACE` | any | No | Kubernetes namespace (default: `oracle-cdc`) |
| `HELM_RELEASE` | any | No | Helm release name (default: `oracle-cdc`) |

## Profiles

| Profile | Description |
|---------|-------------|
| `olr-only` | OLR writes CDC events directly to file (lightweight) |
| `full` | Full pipeline: OLR → Debezium → Kafka → Consumer |

## What Each Step Does

| Step | Description |
|------|-------------|
| `make clean` | Stop containers/pods, remove volumes/PVCs and output files |
| `make up` | Start the stack based on `PROFILE` |
| `make build` | Wait for Oracle, build TPCC schema, enable supplemental logging, restart CDC |
| `make run-bench` | Run HammerDB workload, record timestamps |
| `make report` | Generate HTML report from Prometheus metrics |

## Monitoring During Build/Benchmark

Since `make build` and `make run-bench` are long-running, open a separate terminal to monitor for issues:

### Docker

```bash
# During make build - watch Oracle and HammerDB
docker compose logs -f oracle hammerdb

# During make run-bench (full profile) - watch CDC pipeline
docker compose logs -f dbz olr-dbz kafka

# Watch CDC events being captured
docker compose exec kafka-consumer tail -f /app/output/events.json
```

### Kubernetes

```bash
# During make build
kubectl logs -n oracle-cdc deployment/oracle -f
kubectl logs -n oracle-cdc job/hammerdb-build -f

# During make run-bench
kubectl logs -n oracle-cdc deployment/oracle-cdc-olr -f
kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium -f
```

### What to Watch For

- **Oracle**: ORA-* errors, tablespace issues
- **HammerDB**: Connection failures, schema build errors
- **OLR**: Checkpoint issues, redo log gaps
- **Debezium**: Kafka connection errors, schema registry issues
- **Kafka**: Broker errors, topic creation failures

---

# Metrics Reference

## OLR Metrics

| Metric | Description |
|--------|-------------|
| `dml_ops{filter="out"}` | DML operations output (by table, type) |
| `bytes_parsed` | Bytes of redo log parsed |
| `bytes_sent` | Bytes sent to output |
| `messages_sent` | Messages sent |

## Oracle Exporter Metrics

| Metric | Description |
|--------|-------------|
| `oracledb_dml_redo_entries` | Redo log entries (proxy for DML rate) |
| `oracledb_dml_redo_bytes` | Total redo data generated |
| `oracledb_activity_user_commits` | Commit count |

---

# Expected Results

## OLR-Only (4 VUs, 10 warehouses, 5 min)

| Metric | Value |
|--------|-------|
| Oracle Peak CPU | ~160% (of 200% Free limit) |
| OLR Memory | ~2 GiB |

## Full Profile (4 VUs, 10 warehouses, 5 min)

| Metric | Value |
|--------|-------|
| Debezium Throughput | ~6,000 events/sec |
| Oracle Peak CPU | ~160% (of 200% Free limit) |
| OLR Memory | ~2 GiB |
| Debezium Memory | ~630 MiB |

---

# See Also

- [HOWTO_HAMMERDB.md](HOWTO_HAMMERDB.md) - HammerDB commands, web service, REST API
