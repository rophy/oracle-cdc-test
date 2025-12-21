# Known Issues

See open issues at: https://github.com/rophy/oracle-cdc-test/issues

## OLR Hangs with IOT Tables

**Status**: Fixed
**Issue**: [#4](https://github.com/rophy/oracle-cdc-test/issues/4)

## Oracle 23ai Free Lite - DBMS_METADATA Broken

**Status**: Workaround applied

The Oracle official `container-registry.oracle.com/database/free:23.5.0.0-lite` image has a broken `DBMS_METADATA` package due to invalid XDB components. This affects OLR's schema discovery.

**Workaround**: Use `gvenzl/oracle-free:23.9-slim-faststart` instead. The gvenzl slim-faststart image properly handles XDB dependencies while still being a smaller image.

## OLR/Debezium Stalling During HammerDB Workload

**Status**: Fixed

During stress testing with HammerDB (8 VUs, 5 min duration), OLR and Debezium would stop processing events while containers remained running.

**Root Cause**: OLR memory exhaustion during high-throughput workload.

1. **Memory Limit**: OLR's default `max-mb` is 2048 MB. Under heavy load, it exceeded this limit and started swapping transactions to disk.

2. **Open Transactions**: Long-running transactions during HammerDB workload caused OLR to track uncommitted changes in swap files, consuming memory.

3. **Confirmation Lag**: The gap between OLR's processed SCN and Debezium's confirmed SCN grew too large, causing backpressure.

4. **Deadlock**: OLR waited on internal mutex (futex_wait) while Debezium was blocked reading from socket. Neither could proceed.

**Fix applied** in `config/openlogreplicator/OpenLogReplicator.json`:
```json
{
  "source": [{
    "memory": {
      "min-mb": 256,
      "max-mb": 4096
    }
  }],
  "target": [{
    "writer": {
      "queue-size": 200000
    }
  }]
}
```

Note: The `memory` element must be inside `source`, not at the root level.

**Debugging tips** (if issue recurs):
```bash
# Check for swap files (indicates memory pressure)
docker compose exec olr ls -la /opt/OpenLogReplicator/*.swap

# Check OLR memory usage
docker stats --no-stream oracle-cdc-test-olr-1

# Check thread states
docker compose exec olr cat /proc/$(pgrep OpenLogReplicator)/wchan
docker compose exec dbz jcmd 1 Thread.print | grep -A5 "change-event-source-coordinator"

# Check checkpoint gap (confirmed vs processed)
docker compose exec olr cat /opt/OpenLogReplicator/checkpoint/ORACLE-chkpt.json
```
