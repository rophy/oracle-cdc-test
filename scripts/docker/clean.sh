#!/bin/bash
# Clean output files and remove everything including volumes
set -e
docker compose --profile=olr-only --profile=full down -v
docker compose --profile=clean run --rm clean
