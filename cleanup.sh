#!/bin/bash
set -e

echo "Cleaning up test objects..."

# Function to check if container is running
is_container_running() {
    docker ps -q -f name=$1 | grep -q .
    return $?
}

# Clean up data directories if containers are running
if is_container_running pg16_primary; then
    echo "Cleaning primary data directory..."
    docker exec -it pg16_primary rm -rf /var/lib/pgsql/16/data/*
fi

if is_container_running pg16_standby; then
    echo "Cleaning standby data directory..."
    docker exec -it pg16_standby rm -rf /var/lib/pgsql/16/data/*
fi

if is_container_running pg16_subscriber; then
    echo "Cleaning subscriber data directory..."
    docker exec -it pg16_subscriber rm -rf /var/lib/pgsql/14/data/*
fi

# Stop and remove containers
echo "Stopping and removing containers..."
docker stop pg16_primary pg16_standby pg16_subscriber 2>/dev/null || true
docker rm pg16_primary pg16_standby pg16_subscriber 2>/dev/null || true

# Remove project-prefixed volumes
echo "Removing Docker volumes..."
docker volume rm pg_failover_slots_pg16_primary_data pg_failover_slots_pg16_standby_data pg_failover_slots_pg16_subscriber_data 2>/dev/null || true

echo "Cleanup completed. All containers and volumes have been removed." 