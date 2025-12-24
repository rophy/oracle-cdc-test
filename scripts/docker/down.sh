#!/bin/bash
# Stop all containers (preserves volumes)
set -e
docker compose --profile=olr-only --profile=full down
