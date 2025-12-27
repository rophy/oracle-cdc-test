# HammerDB Usage Guide

This document covers how to use HammerDB for TPROC-C benchmarking and how to retrieve job metrics via the REST API.

## Container Commands

The HammerDB container supports the following commands:

```bash
# Build TPROC-C schema (10 warehouses, 4 VUs)
docker compose exec hammerdb /scripts/entrypoint.sh build

# Run TPROC-C workload
docker compose exec hammerdb /scripts/entrypoint.sh run

# Delete TPROC-C schema
docker compose exec hammerdb /scripts/entrypoint.sh delete

# Interactive CLI shell
docker compose exec hammerdb /scripts/entrypoint.sh shell

# Run one-shot TCL command
docker compose exec hammerdb /scripts/entrypoint.sh cmd "puts [jobs]"

# Start web service (default on container startup)
docker compose exec hammerdb /scripts/entrypoint.sh web
```

> **Note**: `build` takes ~2-3 minutes and `run` takes ~9 minutes (2 min rampup + 5 min test). These are long-running jobs - consider running in background and monitoring logs:
> ```bash
> # Run in background
> docker compose exec -d hammerdb /scripts/entrypoint.sh build
>
> # Monitor progress
> docker compose logs -f hammerdb
> ```

## Web Service

The HammerDB web service runs on port 8080 inside the container. It provides:
- HTML interface for viewing job results in a browser
- JSON API endpoints for programmatic access

### Accessing the Web Service

From inside the container:
```bash
docker compose exec hammerdb curl http://localhost:8080/jobs
```

To access from host, expose port 8080 in docker-compose.yml:
```yaml
hammerdb:
  ports:
    - "8080:8080"
```

## REST API Endpoints

### List Jobs (HTML only)

```bash
curl http://localhost:8081/jobs
```

Returns HTML. To get job IDs, parse the HTML or use CLI:

```bash
# Parse job IDs from HTML
curl -s http://localhost:8080/jobs | grep -oP 'jobid=\K[^&]+'

# Or use CLI command
docker compose exec hammerdb /scripts/entrypoint.sh cmd "puts [jobs]"
# Returns: ["JOBID1", "JOBID2", ...]
```

### Job Result Data (JSON)

Get benchmark results including NOPM and TPM:

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&resultdata"
```

Response:
```json
[
  "69467B60646503E283231303",
  "2025-12-20 10:33:04",
  "1 Active Virtual Users configured",
  "TEST RESULT : System achieved 3290 NOPM from 6828 Oracle TPM"
]
```

### Job Configuration (JSON)

Get the benchmark configuration used for the job:

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&dict"
```

Response:
```json
{
  "connection": {
    "system_user": "system",
    "system_password": "OraclePwd123",
    "instance": "oracle:1521/FREEPDB1",
    "rac": "0"
  },
  "tpcc": {
    "count_ware": "1",
    "num_vu": "1",
    "tpcc_user": "TPCC",
    "tpcc_pass": "TPCCPWD",
    "ora_driver": "timed",
    "rampup": "0",
    "duration": "1",
    ...
  }
}
```

### Job Status (JSON)

Get virtual user execution status:

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&status"
```

Response:
```json
[
  "0", "Vuser 1:RUNNING",
  "0", "Vuser 2:RUNNING",
  "0", "Vuser 1:FINISHED SUCCESS",
  "0", "Vuser 2:FINISHED SUCCESS",
  "0", "ALL VIRTUAL USERS COMPLETE"
]
```

### Job Timestamp (JSON)

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&timestamp"
```

Response:
```json
{"69467B60646503E283231303": {"2025-12-20": "10:33:04"}}
```

### Job Output Logs (JSON)

Get full execution output:

```bash
curl "http://localhost:8080/jobs?jobid=JOBID"
```

Returns JSON array of log entries.

### Timing Data (JSON)

Get per-transaction timing data (requires `ora_timeprofile=true`):

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&timingdata"
```

### Result Chart (HTML)

Get ECharts visualization:

```bash
curl "http://localhost:8080/jobs?jobid=JOBID&result"
```

Returns HTML with embedded ECharts JavaScript.

## API Summary

| Endpoint | Format | Description |
|----------|--------|-------------|
| `/jobs` | HTML | Job list (browser view) |
| `/jobs?jobid=XXX` | JSON | Job output logs |
| `/jobs?jobid=XXX&resultdata` | JSON | NOPM/TPM metrics |
| `/jobs?jobid=XXX&dict` | JSON | Job configuration |
| `/jobs?jobid=XXX&status` | JSON | Vuser execution status |
| `/jobs?jobid=XXX&timestamp` | JSON | Job timestamp |
| `/jobs?jobid=XXX&timingdata` | JSON | Transaction timing |
| `/jobs?jobid=XXX&result` | HTML | ECharts visualization |

## Example: Get Latest Job Metrics

```bash
# Get latest job ID
JOBID=$(docker compose exec hammerdb curl -s http://localhost:8080/jobs | grep -oP 'jobid=\K[^&]+' | tail -1)

# Get metrics
docker compose exec hammerdb curl -s "http://localhost:8080/jobs?jobid=$JOBID&resultdata"

# Get config
docker compose exec hammerdb curl -s "http://localhost:8080/jobs?jobid=$JOBID&dict"
```

## Custom Workload via TCL

Run a custom single-warehouse build:

```bash
docker compose exec hammerdb /scripts/entrypoint.sh cmd "
dbset db ora
diset connection system_user system
diset connection system_password OraclePwd123
diset connection instance oracle:1521/FREEPDB1
diset tpcc tpcc_user TPCC
diset tpcc tpcc_pass TPCCPWD
diset tpcc tpcc_def_tab TBLS1
diset tpcc count_ware 1
diset tpcc num_vu 1
buildschema
"
```

## Jobs Database

Job data is stored in SQLite at `/tmp/hammer.DB` inside the container. This is mapped to `./output/hammerdb/hammer.DB` on the host.

Query directly:
```bash
docker compose exec hammerdb sqlite3 /tmp/hammer.DB "SELECT jobid FROM JOBMAIN;"
```
