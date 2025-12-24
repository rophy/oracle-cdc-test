# Performance Testing Guide

This guide covers how to run HammerDB stress tests and generate performance reports.

## Platform-Specific Guides

| Platform | Guide | Description |
|----------|-------|-------------|
| **Docker Compose** | [HOWTO_PERF_DOCKER.md](HOWTO_PERF_DOCKER.md) | Local development, quick testing |
| **Kubernetes** | [HOWTO_PERF_K8S.md](HOWTO_PERF_K8S.md) | Production-like environment, uses Helm chart |

## Quick Start

```bash
# Set deployment mode (required)
export DEPLOY_MODE=docker  # or: export DEPLOY_MODE=k8s

# Deploy full pipeline
make up-full

# Wait for Oracle, then build TPCC schema
# (see platform-specific guides for details)

# Run benchmark
make run-bench

# Generate report
make report
```

## Makefile Targets

All targets require `DEPLOY_MODE` environment variable to be set.

| Target | Description |
|--------|-------------|
| `make up` | Start base stack (Oracle + monitoring) |
| `make up-olr` | Start with OLR direct to file |
| `make up-full` | Start full pipeline (OLR -> Debezium -> Kafka) |
| `make down` | Stop all containers/pods (preserves volumes/PVCs) |
| `make clean` | Clean output files and remove everything including volumes/PVCs |
| `make run-bench` | Run HammerDB benchmark with timestamp tracking |
| `make report` | Generate performance report from last benchmark run |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DEPLOY_MODE` | Yes | `docker` or `k8s` |
| `K8S_NAMESPACE` | No | Kubernetes namespace (default: `oracle-cdc`) |
| `HELM_RELEASE` | No | Helm release name (default: `oracle-cdc`) |

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
