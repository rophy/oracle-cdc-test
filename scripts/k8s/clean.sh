#!/bin/bash
# Clean everything including PVCs
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Cleaning up namespace: $NAMESPACE"

# Uninstall helm release
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Release not found"

# Wait for pods to actually terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod --all -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

# Delete PVCs (must wait for pods to be gone first, as bound PVCs are protected)
echo "Deleting PVCs..."
kubectl delete pvc --all -n "$NAMESPACE" --wait=true 2>/dev/null || true

# Clean local output files
echo "Cleaning local output files..."
rm -rf output/hammerdb/*.txt output/olr/*.json 2>/dev/null || true

echo "Cleanup complete."
