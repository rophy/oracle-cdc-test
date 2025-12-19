# Known Issues

## OLR Network Writer Stalls When Streaming to Debezium

### Summary
OpenLogReplicator 1.8.7 stalls after processing 3-4 archived redo log sequences when using the network writer to stream to Debezium. The issue does not occur with file output.

### Symptoms
- OLR processes 3-4 archive log sequences after startup
- Then stops logging and stops processing new redo entries
- All threads become idle (waiting on futex)
- TCP connection to Debezium remains established
- No errors in logs
- Restarting OLR resumes processing for another 3-4 sequences, then stalls again

### Environment
- OpenLogReplicator: 1.8.7
- Debezium Server: 3.3.2.Final
- Oracle Database: 23ai Free (23.5.0.0-lite)
- Adapter: Debezium OLR adapter (network connection on port 9000)

### Reproduction Steps
1. Start the CDC stack with OLR network writer configured
2. Generate significant database activity (e.g., HammerDB TPCC workload)
3. Observe OLR logs - it will process a few sequences then stop
4. Check thread state: all threads in `futex_wait_queue`
5. Restart OLR - it continues for a few more sequences, then stalls again

### Diagnostic Commands
```bash
# Check OLR thread states
for tid in $(docker compose exec olr ls /proc/7/task/); do
  echo "Thread $tid: $(docker compose exec olr cat /proc/7/task/$tid/wchan 2>/dev/null)"
done

# Check TCP connection status (connection remains established)
docker compose exec olr cat /proc/net/tcp

# Check last processed sequence
docker compose logs olr | grep "processing redo log" | tail -5
```

### Test Results

| Output Mode | Sequences Processed | Events Captured | Result |
|-------------|---------------------|-----------------|--------|
| Network (Debezium) | 3-4 per restart | ~120K per restart | **Stalls repeatedly** |
| File | All 22 sequences | 4.3M | **Works perfectly** |

### Workarounds

#### Option 1: Periodic Restarts (Not Recommended)
Script automated restarts of OLR until all archived logs are processed. This is unreliable and loses real-time CDC capability.

#### Option 2: File Output Mode
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

Then use a separate process to read the file and publish to Kafka.

### Root Cause Analysis
The issue is isolated to OLR's network writer component:
- Core redo log parsing works correctly (proven by file output test)
- Schema discovery and metadata updates work correctly
- The stall occurs during network streaming, likely due to:
  - Backpressure handling issue with Debezium client
  - TCP socket write blocking without timeout
  - Thread synchronization issue in the network writer

### Related Configuration
OLR network writer config that exhibits the issue:
```json
{
  "target": [
    {
      "alias": "debezium",
      "source": "FREE",
      "writer": {
        "type": "network",
        "uri": "0.0.0.0:9000"
      }
    }
  ]
}
```

### Status
- **Confirmed**: Issue is reproducible
- **Isolated**: Confirmed to be in network writer (file output works)
- **Unresolved**: No fix available, workaround is to use file output

### References
- OLR GitHub: https://github.com/bersler/OpenLogReplicator
- Debezium OLR Adapter: https://debezium.io/documentation/reference/stable/connectors/oracle.html#oracle-openlogreplicator
