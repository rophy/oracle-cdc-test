#!/bin/bash
# Start with OLR direct to file
set -e
docker compose --profile=olr-only up -d
