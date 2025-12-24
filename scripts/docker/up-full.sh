#!/bin/bash
# Start full pipeline (OLR → Debezium → Kafka)
set -e
docker compose --profile=full up -d
