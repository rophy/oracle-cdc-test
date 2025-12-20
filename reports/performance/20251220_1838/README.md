# Performance Test Report - 2025-12-20 18:38

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Test Date | 2025-12-20 18:38 UTC |
| Virtual Users | 12 |
| Warehouses | 20 |
| Rampup Time | 2 minutes |
| Test Duration | 5 minutes |
| Total Test Time | 7 minutes |

## Infrastructure

| Component | Image/Version |
|-----------|---------------|
| Oracle | gvenzl/oracle-free:23.9-slim-faststart |
| OpenLogReplicator | rophy/openlogreplicator:1.8.7 |
| HammerDB | tpcorg/hammerdb:v4.10 |

## Results Summary

### OLR (OpenLogReplicator) Performance

| Metric | Value |
|--------|-------|
| Peak Throughput | ~897 events/sec |
| Average Throughput | ~540 events/sec |
| Total DML Operations | ~324,000 (from Prometheus dml_ops) |
| Output File Size | 34 GB (includes buildschema data) |

**Note**: The 34 GB output file (20.9M lines) includes the initial buildschema data load (~4M rows across 20 warehouses), not just the workload events.

### Events by Table (filter=out)

| Table | Operation | Count |
|-------|-----------|-------|
| TPCC.STOCK | update | 153,922 |
| TPCC.CUSTOMER | update | 38,253 |
| TPCC.DISTRICT | update | 30,844 |
| TPCC.WAREHOUSE | update | 15,451 |
| TPCC.HISTORY | insert | 15,451 |
| TPCC.ORDERS | insert | 15,393 |
| TPCC.ORDERS | update | 15,070 |
| (commits) | commit | 39,235 |

### HammerDB Performance

| Metric | Value |
|--------|-------|
| Average TPM | 5,265 |
| Peak TPM | 11,046 |
| Average TPS | ~88 transactions/sec |

### Event Amplification

- **HammerDB transactions**: ~26,400 (5,265 TPM × 5 min)
- **OLR DML events**: ~324,000 (from Prometheus)
- **Ratio**: ~12 CDC events per TPCC transaction

## Resource Usage

### During Test (from Prometheus)

| Container | Peak CPU | Avg CPU | Peak Memory |
|-----------|----------|---------|-------------|
| Oracle | 44.3% | 28.5% | 9.1 GB |
| OLR | 2.2% | 1.4% | 649 MB |

### Post-Test Snapshot

| Container | CPU | Memory |
|-----------|-----|--------|
| Oracle | 100% | 2.65 GB / 8 GB |
| OLR | 0.5% | 103 MB |
| HammerDB | 0% | 14 MB |

## Charts

See [charts.html](charts.html) for interactive time-series visualizations of:
- CPU usage over time
- Memory usage over time
- OLR DML processing rate
- Events by table breakdown

## Key Observations

1. **OLR is efficient** - Processing ~540-900 events/sec with only 2% CPU and ~650 MB memory

2. **Oracle CPU is moderate** - Running at 20-44% during workload, but spikes to 100% post-workload (catching up on redo log archiving)

3. **~12 CDC events per transaction** - Each TPCC transaction generates about 12 DML operations (updates to STOCK, DISTRICT, CUSTOMER, etc.)

4. **STOCK table dominates** - 153,922 updates (47% of table-level events), reflecting TPCC's stock level update pattern

## Test Artifacts

- HammerDB log: `output/hammerdb/run_20251220_183846.log`
- OLR events: `output/olr/events.json` (34 GB)
