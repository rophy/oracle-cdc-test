#!/bin/bash
# Start base services (oracle, hammerdb, monitoring)
# CDC components are started by build.sh after schema is created
set -e

docker compose up -d
