# Known Issues

## Debezium Crashes on Unknown Tables (OLR Adapter)

### Summary
Debezium Server 3.3.2.Final crashes when receiving CDC events for tables it doesn't know about (not in its schema history). This commonly occurs when new tables are created after Debezium's initial snapshot, such as during HammerDB TPCC schema creation.

### Root Cause
When OLR sends a DML event for a table Debezium hasn't seen before, Debezium attempts to fetch the table's metadata using `getTableMetadataDdl()`. This method fails with:

```
io.debezium.DebeziumException: Cannot execute without committing because auto-commit is enabled
```

The crash occurs in `OpenLogReplicatorStreamingChangeEventSource.potentiallyEmitSchemaChangeForUnknownTable()`.

### Symptoms
1. **Debezium logs show**:
   ```
   ERROR Failed: Cannot execute without committing because auto-commit is enabled
   ERROR Producer failure
   ERROR Connector completed: success = 'false'
   ```

2. **OLR logs show**:
   ```
   WARN 10061 network error, errno: 32, message: Broken pipe
   ```

3. **Cycle repeats**: Debezium restarts (due to `restart: on-failure`), reconnects to OLR, receives the same event, crashes again.

### Environment
- Debezium Server: 3.3.2.Final
- OpenLogReplicator: 1.8.7
- Oracle Database: 23ai Free (23.5.0.0-lite)
- Adapter: Debezium OLR adapter

### Reproduction Steps
1. Start the CDC stack with Debezium and OLR
2. Wait for Debezium to complete initial snapshot and start streaming
3. Create new tables in a schema that OLR is configured to capture (e.g., run HammerDB build)
4. Observe Debezium crash loop and OLR "Broken pipe" errors

### What We Tried (Did Not Help)
Adding these Debezium configuration options did NOT prevent the crash:
```properties
debezium.source.include.schema.changes=false
debezium.source.schema.history.internal.store.only.captured.tables.ddl=true
```

### Workarounds

#### Option 1: Stop Debezium During Schema Changes
Stop Debezium before creating new tables, then restart after:
```bash
docker compose stop dbz
# Create tables (e.g., HammerDB build)
docker compose start dbz
```

#### Option 2: Use OLR File Output
Configure OLR to write to a file instead of streaming to Debezium:
```json
{
  "target": [
    {
      "alias": "file",
      "source": "FREE",
      "writer": {
        "type": "file",
        "output": "/output/events.json"
      }
    }
  ]
}
```

With file output, OLR processes all events without issues (tested: 4.3M events across 22 archive log sequences). A separate process can then read the file and publish to Kafka.

### Misdiagnosis Note
This issue was initially misdiagnosed as "OLR network writer stalling." The actual sequence of events:

1. OLR sends event for unknown table to Debezium
2. Debezium crashes trying to fetch metadata
3. TCP connection breaks, OLR logs "Broken pipe"
4. OLR waits for new client connection (appears to "stall")
5. Debezium restarts and reconnects
6. Same event causes another crash

The "stalling" was actually OLR waiting for a client after Debezium crashed. OLR itself works correctly - the issue is entirely on the Debezium side.

### Status
- **Root Cause**: Debezium OLR adapter bug when handling unknown tables
- **Workaround**: Stop Debezium during schema changes, or use OLR file output
- **Fix**: Requires Debezium code change to handle unknown tables gracefully

### References
- Debezium OLR Adapter: https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-openlogreplicator
- OLR GitHub: https://github.com/bersler/OpenLogReplicator
