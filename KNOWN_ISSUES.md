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

#### Technical Analysis

The bug is a **JDBC connection state management issue** in the OLR adapter:

1. **Initial setup** (`OpenLogReplicatorStreamingChangeEventSource.execute()` line 110):
   ```java
   this.jdbcConnection.setAutoCommit(false);
   ```

2. **The problem**: If the JDBC connection is ever dropped and re-established (timeout, network issue, Oracle restart), the new connection defaults to `autoCommit=true` per JDBC specification.

3. **Trigger**: When `potentiallyEmitSchemaChangeForUnknownTable()` calls `getTableMetadataDdl()`:
   - `getTableMetadataDdl()` calls `executeWithoutCommitting()`
   - `executeWithoutCommitting()` calls `connection()` which may create a **new** JDBC connection
   - The safeguard check `if (conn.getAutoCommit())` fails because the new connection has auto-commit enabled

4. **Code path** (`JdbcConnection.java` lines 906-925):
   ```java
   public synchronized Connection connection(boolean executeOnConnect) throws SQLException {
       if (!isConnected()) {
           establishConnection();  // Creates NEW connection with autoCommit=true
           // ... no setAutoCommit(false) here!
       }
       return conn;
   }
   ```

#### Why Other Adapters Don't Have This Issue

The `OracleSignalBasedIncrementalSnapshotChangeEventSource` handles this correctly by wrapping the call:
```java
protected String getTableDDL(TableId dataCollectionId) throws SQLException {
    this.connection.setAutoCommit(false);  // Set before
    String ddlString = this.connection.getTableMetadataDdl(dataCollectionId);
    this.connection.setAutoCommit(true);   // Reset after
    return ddlString;
}
```

The OLR adapter's `potentiallyEmitSchemaChangeForUnknownTable()` lacks this protection.

#### Fix

The fix needs to be in `OracleConnection.getTableMetadataDdl()`, NOT in the caller. This is because `getTableMetadataDdl()` internally calls `prepareQueryAndMap()` which may re-establish the connection, resetting auto-commit.

Add `setAutoCommit(false)` in TWO places inside `OracleConnection.getTableMetadataDdl()`:

```java
public String getTableMetadataDdl(TableId tableId) throws SQLException, NonRelationalTableException {
    try {
        // First query to check if table exists
        if (prepareQueryAndMap(...) == 0) {
            throw new NonRelationalTableException(...);
        }

        // FIX 1: Add after prepareQueryAndMap, before executeWithoutCommitting
        setAutoCommit(false);

        // These calls require auto-commit disabled
        executeWithoutCommitting("begin dbms_metadata.set_transform_param...STORAGE...");
        executeWithoutCommitting("begin dbms_metadata.set_transform_param...SEGMENT_ATTRIBUTES...");
        executeWithoutCommitting("begin dbms_metadata.set_transform_param...SQLTERMINATOR...");
        return prepareQueryAndMap("SELECT dbms_metadata.get_ddl...");
    }
    finally {
        // FIX 2: Also add in finally block - prepareQueryAndMap above may have reconnected
        setAutoCommit(false);
        executeWithoutCommitting("begin dbms_metadata.set_transform_param...DEFAULT...");
    }
}
```

A patched image is available: `debezium-server:patched`

Build with:
```bash
docker build -f refs/Dockerfile.debezium-patched -t debezium-server:patched .
```

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
- **Root Cause**: JDBC connection state not preserved after reconnection in OLR adapter
- **Workaround**: Stop Debezium during schema changes, or use OLR file output
- **Fix**: Add `setAutoCommit(false)` calls inside `OracleConnection.getTableMetadataDdl()` (see above)
- **Patched Image**: `docker build -f refs/Dockerfile.debezium-patched -t debezium-server:patched .`
- **Upstream**: No existing JIRA issue found - consider filing a bug report

---

## Oracle 23ai Free Lite Image: Broken DBMS_METADATA

### Summary
The Oracle 23ai Free "lite" container image ships with a broken `SYS.DBMS_METADATA` package. This is a **shipping defect** in the lite image - the Oracle XML Database (XDB) component was partially removed to reduce image size, but DBMS_METADATA depends on XDB views that no longer exist.

### Error
```
ORA-04063: package body "SYS.DBMS_METADATA" has errors
```

Or in some cases:
```
ORA-00600: internal error code, arguments: [17287], ...
```

### Root Cause
The lite image has XDB in a broken `REMOVING` state:

```sql
-- Check component status
SELECT comp_id, comp_name, status FROM dba_registry WHERE comp_id IN ('XML', 'XDB');

-- Result:
-- XML    Oracle XDK              VALID
-- XDB    Oracle XML Database     REMOVING   <-- Problem!
```

The dependency chain:
1. `SYS.DBA_XMLSCHEMA_LEVEL_VIEW` - **does not exist** (removed with XDB)
2. `SYS.KU$_XMLSCHEMA_VIEW` - INVALID (depends on missing view)
3. `SYS.DBMS_METADATA` package body - INVALID (depends on KU$_XMLSCHEMA_VIEW)

```sql
-- Check DBMS_METADATA errors
SELECT text FROM dba_errors
WHERE owner = 'SYS' AND name = 'DBMS_METADATA' AND type = 'PACKAGE BODY';

-- Result:
-- PL/SQL: ORA-04063: view "SYS.KU$_XMLSCHEMA_VIEW" has errors
```

### Verification
This issue exists on a **fresh** lite image instance - no configuration or setup required to reproduce:

```bash
docker run -d --name oracle-test container-registry.oracle.com/database/free:23.5.0.0-lite
# Wait for startup...
docker exec oracle-test sqlplus -S / as sysdba <<< "SELECT dbms_metadata.get_ddl('TABLE', 'DUAL', 'SYS') FROM dual;"
# Result: ORA-04063: package body "SYS.DBMS_METADATA" has errors
```

### Impact
- Debezium cannot fetch DDL metadata for newly created tables
- Any application using `DBMS_METADATA.GET_DDL()` will fail
- The auto-commit fix for the first issue doesn't help - this is a separate Oracle limitation

### Workarounds

#### Option 1: Use Full Oracle Image
Use the non-lite image tag (larger download, ~2GB vs ~500MB):
```
container-registry.oracle.com/database/free:23.5.0.0
```

#### Option 2: Pre-create All Tables
Create all tables before starting Debezium, so it captures them during the initial snapshot and never needs to call `DBMS_METADATA.GET_DDL()`.

#### Option 3: Use LogMiner Instead of OLR
The LogMiner adapter may handle unknown tables differently.

### Status
- **Root Cause**: Oracle 23ai Free lite image ships with XDB partially removed, breaking DBMS_METADATA
- **Scope**: Affects any use of `DBMS_METADATA.GET_DDL()`, not just Debezium
- **Workaround**: Use non-lite image, or pre-create all tables
- **Upstream**: Not yet reported to Oracle - consider filing a bug

### References
- Oracle Container Registry: https://container-registry.oracle.com/ords/ocr/ba/database/free
- Debezium OLR Adapter: https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-openlogreplicator
