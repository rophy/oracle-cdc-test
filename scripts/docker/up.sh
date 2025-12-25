#!/bin/bash
# Start stack based on PROFILE environment variable
set -e

if [ "$PROFILE" = "olr-only" ]; then
    docker compose --profile=olr-only up -d
else
    docker compose --profile=full up -d
fi
