#!/bin/bash

# Complete cleanup script for pglogical2 environment
# This script removes all containers, volumes, networks, and data

set -e

echo "=== Complete Cleanup for pglogical2 Environment ==="

# Stop and remove all containers
echo "Stopping and removing all containers..."
docker-compose down -v --remove-orphans 2>/dev/null || true

# Remove any remaining containers with our project name
echo "Removing any remaining containers..."
docker ps -a --filter "name=pg_ha_env" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Remove all volumes
echo "Removing all volumes..."
docker volume ls --filter "name=pg_ha_env" --format "{{.Name}}" | xargs -r docker volume rm -f 2>/dev/null || true

# Remove all networks
echo "Removing all networks..."
docker network ls --filter "name=pg_ha_env" --format "{{.Name}}" | xargs -r docker network rm -f 2>/dev/null || true

# Remove any orphaned volumes (be careful with this in production)
echo "Removing orphaned volumes..."
docker volume prune -f 2>/dev/null || true

# Remove any orphaned networks
echo "Removing orphaned networks..."
docker network prune -f 2>/dev/null || true

# Clean up any leftover Docker images (optional)
echo "Cleaning up unused images..."
docker image prune -f 2>/dev/null || true

# Remove any data directories that might exist locally
echo "Removing local data directories..."
rm -rf ./data 2>/dev/null || true
rm -rf ./primary/data 2>/dev/null || true
rm -rf ./standby/data 2>/dev/null || true
rm -rf ./subscriber/data 2>/dev/null || true

# Clean up any log files
echo "Cleaning up log files..."
rm -f *.log 2>/dev/null || true
rm -f ./logs/*.log 2>/dev/null || true

# Reset Docker system (optional - be careful in production)
echo "Resetting Docker system..."
docker system prune -f 2>/dev/null || true

echo "=== Cleanup Complete ==="
echo "All containers, volumes, networks, and data have been removed."
echo ""
echo "To start fresh, run:"
echo "  docker-compose up -d"
echo ""
echo "To run the test script:"
echo "  ./test_pglogical2.sh" 