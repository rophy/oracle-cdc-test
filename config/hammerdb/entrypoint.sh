#!/bin/bash
set -e

# Find HammerDB installation directory
HAMMERDB_DIR=$(find /home -maxdepth 1 -type d -name "HammerDB-*" | head -1)
if [ -z "$HAMMERDB_DIR" ]; then
  echo "ERROR: HammerDB directory not found"
  exit 1
fi
cd "$HAMMERDB_DIR"

echo "HammerDB Performance Test Client"
echo "================================="
echo ""
echo "Available commands:"
echo "  build    - Build TPROC-C schema"
echo "  run      - Run TPROC-C workload"
echo "  delete   - Delete TPROC-C schema"
echo "  shell    - Interactive hammerdbcli shell"
echo ""

case "${1:-shell}" in
  build)
    echo "Building TPROC-C schema..."
    ./hammerdbcli auto /scripts/buildschema.tcl
    ;;
  run)
    echo "Running TPROC-C workload..."
    ./hammerdbcli auto /scripts/runworkload.tcl
    ;;
  delete)
    echo "Deleting TPROC-C schema..."
    ./hammerdbcli auto /scripts/deleteschema.tcl
    ;;
  shell)
    echo "Starting interactive shell..."
    exec ./hammerdbcli
    ;;
  *)
    echo "Unknown command: $1"
    echo "Usage: $0 {build|run|delete|shell}"
    exit 1
    ;;
esac
