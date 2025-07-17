#!/bin/bash
set -e

# Create logs directory and set permissions
mkdir -p /logs
chown -R postgres:postgres /logs

# If this is a standby, we don't need to initialize the database
if [ -f "/var/lib/pgsql/${PG_MAJOR}/data/standby.signal" ]; then
    echo "This is a standby server, skipping initialization..."
    exec "$@"
    exit 0
fi

# Start PostgreSQL in the background
"$@" &
PG_PID=$!

# Wait for PostgreSQL to be ready
until /usr/pgsql-${PG_MAJOR}/bin/pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 3
done

# Ensure testdb exists before running scripts that require it
# psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'testdb'" | grep -q 1 || psql -U postgres -c "CREATE DATABASE testdb;"

# Run initialization scripts
for f in /docker-entrypoint-initdb.d/*; do
    case "$f" in
        *.sh)  echo "$0: running $f"; . "$f" ;;
        *.sql) echo "$0: running $f"; psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname=postgres -f "$f"; echo ;;
        *)     echo "$0: ignoring $f" ;;
    esac
    echo
done

# Keep PostgreSQL running in the foreground
wait $PG_PID 