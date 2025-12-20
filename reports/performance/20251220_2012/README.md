# Performance Test Report - 2025-12-20 20:12 UTC

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Virtual Users | 60 |
| Duration | 10 minutes |
| Start Time | 2025-12-20 20:12:00 UTC |
| End Time | 2025-12-20 20:22:00 UTC |

## Summary Metrics

| Metric | Min | Avg | Max | Total |
|--------|-----|-----|-----|-------|
| Oracle CPU | 3.0% | 20.8% | 34.6% | - |
| OLR CPU | 0.35% | 2.1% | 14.1% | - |
| Oracle Memory | 5.2 GB | 7.6 GB | 7.9 GB | - |
| OLR Memory | 657 MB | 1.2 GB | 5.0 GB | - |
| DML Throughput | 0.1/s | 563/s | 1.1K/s | ~338K events |
| Bytes Sent | 618 MB | 960 MB | 1.29 GB | +674 MB |

## Key Observations

### 1. CPU Underutilization

Oracle CPU peaked at only **34.6% of 200%** (17.3% of available capacity). With 60 virtual users, this indicates significant contention:

- **Lock contention**: TPC-C with high VU-to-warehouse ratio causes transactions to wait for row locks
- **I/O bound**: Database operations involve disk I/O which doesn't consume CPU during waits
- OLR CPU remained very low (~2% avg), indicating it easily kept up with the workload

### 2. OLR Memory Growth

OLR memory grew steadily from **657 MB to 5 GB** during the 10-minute test:

- Linear growth pattern: ~50 MB/minute during active workload
- Large spike at test end (657 MB → 5 GB) suggests batch processing of accumulated redo logs
- May need investigation for longer-running tests to check for memory leaks vs. intentional buffering

### 3. Bursty DML Processing

DML throughput varied significantly (0.1/s to 1.1K/s):

- Pattern typical of redo log-based CDC: OLR reads archived logs in batches
- Peaks correlate with Oracle's redo log switches
- Average sustained rate of **563 events/sec** with peaks at **1,100 events/sec**

### 4. I/O Patterns

| Component | FS Read Avg | FS Write Avg | Notes |
|-----------|-------------|--------------|-------|
| Oracle | 240 KB/s | 10.3 MB/s | Heavy write load (redo + data) |
| OLR | 20.8 MB/s | 1.2 MB/s | Reads redo logs, writes events.json |

- OLR FS Read spike of **395 MB/s** at test end - catching up on accumulated redo logs
- Oracle network TX (31 KB/s avg) much higher than RX (10 KB/s) - client responses larger than requests

### 5. Total Events Captured

- **~338,000 DML events** captured in 10 minutes
- **674 MB** of event data written by OLR
- Average event size: ~2 KB per event

## Files

- `charts.html` - Interactive Chart.js visualization with time-series charts
- `README.md` - This summary

## Recommendations

1. **Reduce VU count or increase warehouses**: 60 VUs on default warehouse count causes excessive contention
2. **Monitor OLR memory**: The 5 GB spike needs investigation for production use
3. **Consider shorter test intervals**: Current metrics capture 30-second averages; finer granularity may reveal more patterns
