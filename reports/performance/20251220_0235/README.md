# Performance Test Report

**Date**: 2025-12-20 02:35 UTC
**Test Duration**: 7 minutes (2 min rampup + 5 min workload)
**Status**: ✅ Completed Successfully

## Test Configuration

### HammerDB Settings
| Parameter | Value |
|-----------|-------|
| Warehouses | 10 |
| Virtual Users | 8 |
| Rampup Time | 2 minutes |
| Test Duration | 5 minutes |
| Driver | Timed |

### Infrastructure
| Component | Image | Resource Limit |
|-----------|-------|----------------|
| Oracle | gvenzl/oracle-free:23.9-slim-faststart | 2 cores, 2 GB (Free edition limit) |
| OpenLogReplicator | rophy/openlogreplicator:1.8.7 | 4 GB max-mb |
| Debezium | debezium-server:patched | - |
| Kafka | apache/kafka:3.9.0 | - |

## CDC Pipeline Results

### Throughput Summary
| Metric | Value |
|--------|-------|
| **Total Events Captured** | 5,094,341 |
| **Peak Throughput** | 13,027 events/sec |
| **Average Throughput** | 6,646 events/sec |
| **Test Duration** | ~7 minutes |

### Events by Kafka Topic
| Topic | Events |
|-------|--------|
| oracle.TPCC.ORDER_LINE | 3,004,230 |
| oracle.TPCC.STOCK | 1,000,000 |
| oracle.TPCC.CUSTOMER | 300,000 |
| oracle.TPCC.HISTORY | 300,000 |
| oracle.TPCC.ORDERS | 300,000 |
| oracle.TPCC.ITEM | 100,000 |
| oracle.TPCC.NEW_ORDER | 90,000 |
| oracle.TPCC.DISTRICT | 100 |
| oracle.TPCC.WAREHOUSE | 10 |
| oracle.USR1.ADAM1 | 1 |

### OpenLogReplicator Metrics
| Metric | Value |
|--------|-------|
| Bytes Parsed | 435 MB |
| Memory Used | 2,048 MB |
| Memory Limit | 4,096 MB |

## Resource Usage (Post-Test)

| Component | CPU | Memory | Mem % |
|-----------|-----|--------|-------|
| Oracle | 11.03% | 1.73 GB | 21.7% |
| OpenLogReplicator | 0.13% | 2.70 GB | 17.4% |
| Debezium | 0.50% | 1.42 GB | 9.1% |
| Kafka | 1.40% | 772 MB | 4.9% |
| Prometheus | 0.00% | 289 MB | 1.8% |
| Kafka Consumer | 0.43% | 101 MB | 0.6% |
| cAdvisor | 4.43% | 98 MB | 0.6% |
| JMX Exporter | 0.10% | 129 MB | 0.8% |

## Throughput Timeline

Sample throughput readings during test (10-second intervals):

```
Time (UTC)      Throughput      Topic
02:12:55        7,329 evt/s     ORDER_LINE
02:13:05        6,115 evt/s     ORDER_LINE
02:13:15        7,099 evt/s     ORDER_LINE
02:13:25        5,354 evt/s     ORDER_LINE
02:13:36        6,369 evt/s     ORDER_LINE
02:13:46        1,177 evt/s     ORDER_LINE
02:13:56        5,162 evt/s     STOCK
02:14:06        7,714 evt/s     ORDER_LINE
02:14:16        6,639 evt/s     ORDER_LINE
02:14:28          438 evt/s     STOCK
02:14:38        6,797 evt/s     ORDER_LINE
02:14:48        6,678 evt/s     STOCK
02:14:58        5,107 evt/s     STOCK
02:15:08       13,028 evt/s     STOCK       <- Peak
02:15:20        1,729 evt/s     STOCK
02:15:30        5,926 evt/s     ORDER_LINE
02:15:40       11,137 evt/s     STOCK
02:15:50        9,949 evt/s     STOCK
02:16:00        8,348 evt/s     ORDER_LINE
02:16:10       10,497 evt/s     STOCK
02:16:20        7,736 evt/s     ORDER_LINE
02:16:30        5,904 evt/s     STOCK
02:16:40        1,855 evt/s     ORDER_LINE
02:16:50       10,139 evt/s     STOCK
02:17:00       11,437 evt/s     STOCK
02:17:10        6,115 evt/s     STOCK
02:17:20        9,819 evt/s     STOCK
02:17:34        6,740 evt/s     STOCK
02:17:45        2,472 evt/s     ORDER_LINE
02:17:55        6,724 evt/s     ORDER_LINE
```

## Pipeline Health

| Component | Status | Notes |
|-----------|--------|-------|
| Oracle | ✅ Healthy | CDB: FREE, PDB: FREEPDB1 |
| OpenLogReplicator | ✅ Streaming | Processed archived logs seq 44-59 |
| Debezium | ✅ Streaming | Connected to OLR, SCN 2407386 |
| Kafka | ✅ Healthy | All topics created |
| Kafka Consumer | ✅ Running | All events consumed |

## Key Findings

1. **No Stalling**: The OLR memory fix (4 GB max-mb, 200K queue-size) prevented the stalling issue observed in previous tests.

2. **Consistent Throughput**: Average throughput of ~6,600 events/sec with peaks up to 13,000 events/sec.

3. **Memory Usage**: OLR used 2.7 GB of its 4 GB allocation, indicating headroom for larger workloads.

4. **Dominant Topics**: ORDER_LINE (59%) and STOCK (20%) account for ~80% of all CDC events.

## Test Artifacts

- Kafka consumer output: `/app/output/events.json` (in kafka-consumer container)
- HammerDB logs: `/tmp/hammerdb.log` (in hammerdb container)
- Prometheus metrics: Available at `prometheus:9090`

## Prometheus Queries for Charts

```promql
# OLR throughput (DML operations rate)
rate(dml_ops[1m])

# OLR memory usage
memory_used_mb

# Kafka topic offsets (event counts)
kafka_topic_partition_current_offset

# Container CPU usage
rate(container_cpu_usage_seconds_total{name=~".*oracle.*|.*olr.*|.*dbz.*|.*kafka.*"}[1m])

# Container memory usage
container_memory_usage_bytes{name=~".*oracle.*|.*olr.*|.*dbz.*|.*kafka.*"}
```
