# Oracle CDC Performance Test Report

## Test Summary

| Parameter | Value |
|-----------|-------|
| **Start Time** | 2025-12-24T04:18:21Z |
| **End Time** | 2025-12-24T04:26:49Z |
| **Duration** | 8 min 28 sec |
| **Profile** | full (OLR -> Debezium -> Kafka) |
| **HammerDB Config** | 4 VUs, 10 warehouses, 5 min timed run + 2 min rampup |

## Results Overview

| Metric | Value |
|--------|-------|
| **Total CDC Events Captured** | 540065 |
| **OLR Bytes Sent** | 642.39 MB |
| **OLR Bytes Parsed** | 705.28 MB |
| **DML Inserts** | 1.50M |
| **DML Updates** | 0.0 |
| **DML Deletes** | 0.0 |
| **Commits** | 15.73K |

## Resource Usage

### CPU Usage (%)
| **oracle** | Min: 0.0% | Avg: 51.5% | Max: 107.8% |
| **olr** | Min: 0.1% | Avg: 0.1% | Max: 0.1% |
| **debezium** | Min: 0.2% | Avg: 0.7% | Max: 1.6% |
| **kafka** | Min: 0.3% | Avg: 22.7% | Max: 115.7% |

### Memory Usage (MB)
| **oracle** | Min: 9591 MB | Avg: 13386 MB | Max: 15936 MB |
| **olr** | Min: 2263 MB | Avg: 2263 MB | Max: 2263 MB |
| **debezium** | Min: 981 MB | Avg: 1035 MB | Max: 1066 MB |
| **kafka** | Min: 1650 MB | Avg: 1914 MB | Max: 2254 MB |

## Oracle Database Metrics
| **Redo Entries/sec** | Min: 1 | Avg: 21580 | Max: 31285 |
| **Est. Total Redo Entries** | ~10.96M |
| **Redo Bytes/sec** | Min: 211 B/s | Avg: 12.85 MB/s | Max: 18.52 MB/s |
| **Est. Total Redo Bytes** | ~6.53 GB |

## CDC Pipeline Performance

| Stage | Metric | Value |
|-------|--------|-------|
| **Oracle** | Total redo generated | See above |
| **OLR** | Bytes parsed | 705.28 MB |
| **OLR** | Bytes sent to Debezium | 642.39 MB |
| **Debezium** | Events produced to Kafka | 540065 |
| **Kafka Consumer** | Events written to file | 540065 |

## Notes

- **Oracle Free limits**: 2 cores (200% max CPU), 2 GB SGA
- **OLR memory**: ~2.3 GB (expected for redo log processing)
- **Test environment**: K3s on AWS EC2
- **Benchmark**: HammerDB TPROC-C (TPC-C like workload)

---
*Generated on 2025-12-24 04:30:49 UTC*