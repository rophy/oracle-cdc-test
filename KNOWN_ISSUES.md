# Known Issues

See open issues at: https://github.com/rophy/oracle-cdc-test/issues

## Oracle 23ai Free Lite - DBMS_METADATA Broken

**Status**: Workaround applied

The Oracle official `container-registry.oracle.com/database/free:23.5.0.0-lite` image has a broken `DBMS_METADATA` package due to invalid XDB components. This affects OLR's schema discovery.

**Workaround**: Use `gvenzl/oracle-free:23.9-slim-faststart` instead. The gvenzl slim-faststart image properly handles XDB dependencies while still being a smaller image.

## OLR/Debezium Stalling During HammerDB Workload

**Status**: Under investigation

During stress testing with HammerDB (8 VUs, 5 min duration), OLR and Debezium may stop processing events while containers remain running.

**Symptoms observed**:
- OLR reports "processing redo" for sequence 59, but 170+ archived logs exist
- Debezium logs stop after ~13 minutes of workload (last log timestamp 23:14:03)
- Both containers show status "Up" in `docker compose ps`
- HammerDB completes successfully with "Vuser X: FINISHED SUCCESS" messages
- Only ~171K events captured vs expected millions

**Potential causes** (under investigation):
- OLR waiting for Debezium acknowledgment (OLR uses network writer, waits for consumer)
- Debezium connection errors during Oracle SHUTDOWN IMMEDIATE in setup
- Resource exhaustion or backpressure

**Debugging steps**:
```bash
# Check if OLR is waiting for Debezium
docker compose logs olr --tail=20 | grep -E "sequence|waiting|ERROR"

# Check Debezium for errors
docker compose logs dbz --tail=50 | grep -E "ERROR|Exception|connection"

# Verify both are processing
docker compose logs -f dbz olr  # Watch in real-time
```
