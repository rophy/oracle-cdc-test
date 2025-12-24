# Performance Testing - Kubernetes

```bash
export DEPLOY_MODE=k8s
```

## Prerequisites

- Kubernetes cluster with kubectl configured
- Helm 3.x installed
- Storage class available for PVCs (e.g., `ebs-gp3` on AWS)

---

## Part 1: Deploy the Stack

### Step 1.1: Deploy

```bash
# Full pipeline (default)
make up-full

# Or OLR-only
make up-olr
```

### Step 1.2: Wait for Pods

```bash
kubectl get pods -n oracle-cdc -w
```

Wait until all pods show `Running` status and are ready (1/1 or 2/2).

### Step 1.3: Wait for Oracle Setup

```bash
until kubectl exec -n oracle-cdc deployment/oracle-cdc-oracle -- ls /opt/oracle/oradata/dbinit 2>/dev/null; do
  echo "Waiting for Oracle setup..."
  sleep 10
done
echo "Oracle setup complete"
```

### Step 1.4: Wait for Debezium Snapshot (Full Profile Only)

```bash
until kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium snapshot..."
  sleep 10
done
echo "Debezium is streaming"
```

---

## Part 2: Build TPCC Schema and Run Benchmark

### Step 2.1: Build TPCC Schema

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-hammerdb -- /scripts/entrypoint.sh build
```

### Step 2.2: Enable Supplemental Logging

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-oracle -- sqlplus -S / as sysdba <<'EOF'
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER TABLE TPCC.CUSTOMER ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.DISTRICT ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.HISTORY ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ITEM ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.NEW_ORDER ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.ORDER_LINE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.STOCK ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE TPCC.WAREHOUSE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER SYSTEM ARCHIVE LOG CURRENT;
EXIT;
EOF
```

### Step 2.3: Restart OLR and Debezium

```bash
kubectl rollout restart deployment/oracle-cdc-olr deployment/oracle-cdc-debezium -n oracle-cdc
kubectl rollout status deployment/oracle-cdc-olr -n oracle-cdc --timeout=120s
kubectl rollout status deployment/oracle-cdc-debezium -n oracle-cdc --timeout=120s
```

### Step 2.4: Wait for Debezium to Stream Again

```bash
until kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium 2>&1 | grep -q "Starting streaming"; do
  echo "Waiting for Debezium..."
  sleep 10
done
echo "Debezium is streaming"
```

> **Note**: The Kubernetes helm chart uses a reduced OLR `queue-size` (10000 vs 200000 in Docker Compose) to prevent a backpressure deadlock. See `KNOWN_ISSUES.md` for details.

### Step 2.5: Run Benchmark

```bash
make run-bench
```

This automatically records start/end timestamps and saves logs to `output/hammerdb/`.

---

## Part 3: Monitoring

### Check Pod Status

```bash
kubectl get pods -n oracle-cdc
```

### View Logs

```bash
kubectl logs -n oracle-cdc deployment/oracle-cdc-oracle -f         # Oracle
kubectl logs -n oracle-cdc deployment/oracle-cdc-olr -f            # OLR
kubectl logs -n oracle-cdc deployment/oracle-cdc-debezium -c debezium -f  # Debezium
kubectl logs -n oracle-cdc deployment/oracle-cdc-kafka-consumer -f  # Kafka consumer
```

### Check CDC Events

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-kafka-consumer -- wc -l /app/output/events.json
```

### Check OLR Metrics

```bash
kubectl exec -n oracle-cdc deployment/oracle-cdc-hammerdb -- \
  curl -s http://oracle-cdc-olr:9161/metrics | grep -E "dml_ops|bytes_sent"
```

---

## Part 4: Generate Report

### Prerequisites

```bash
pip install -r scripts/report-generator/requirements.txt
```

### Generate Report

```bash
make report
```

This automatically reads timestamps from `output/hammerdb/` and generates an HTML report.

### Manual Report Generation

```bash
START=$(cat output/hammerdb/RUN_START_TIME.txt)
END=$(cat output/hammerdb/RUN_END_TIME.txt)
REPORT_DIR="reports/performance/$(date +%Y%m%d_%H%M)"

python3 scripts/report-generator/k8s_report.py \
    --start "$START" \
    --end "$END" \
    --containers oracle,olr,debezium,kafka,kafka-consumer \
    --namespace oracle-cdc \
    --title "Full Pipeline Performance Test (K8s)" \
    --output "$REPORT_DIR/report.html"
```

---

## Part 5: Cleanup

```bash
make down   # Stop pods (preserves PVCs)
make clean  # Remove everything including PVCs
```
