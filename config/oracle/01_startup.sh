#!/bin/bash
# Oracle startup script with idempotency guard
# This runs on every container start but only executes setup once
# See: https://github.com/oracle/docker-images/issues/2644

DB_INITIALISED="/opt/oracle/oradata/dbinit"

if [ -f "${DB_INITIALISED}" ]; then
    echo "Database already initialized, skipping setup"
    exit 0
fi

echo "Running first-time database setup..."
sqlplus -S / as sysdba @/container-entrypoint-startdb.d/setup.ddl

if [ $? -eq 0 ]; then
    touch "${DB_INITIALISED}"
    echo "Database setup completed successfully"
else
    echo "Database setup failed!"
    exit 1
fi
