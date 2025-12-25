# Performance Testing

## Quick Start

```bash
export DEPLOY_MODE=docker  # or k8s
export PROFILE=full        # or olr-only

make clean      # Remove previous run
make up         # Start stack
make build      # Build TPCC schema and configure CDC
make run-bench  # Run benchmark
make report     # Generate report
```

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

## Monitoring

### Docker

```bash
docker compose logs -f olr-file          # OLR logs (olr-only)
docker compose logs -f dbz olr-dbz       # CDC logs (full)
tail -f ./output/olr/events.json         # CDC events (olr-only)
```

### Kubernetes

```bash
kubectl logs -n oracle-cdc deployment/oracle-cdc-olr -f
kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium -f
```

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
