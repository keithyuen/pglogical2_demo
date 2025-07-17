#!/bin/bash
set -e

echo "Waiting for 30 seconds before promoting standby..."
sleep 30

echo "Attempting to promote standby..."
if psql -U postgres -c "SELECT pg_promote();"; then
    echo "Standby successfully promoted to primary"
else
    echo "Failed to promote standby"
    exit 1
fi

# Wait for promotion to complete
echo "Waiting for promotion to complete..."
sleep 10

# Verify promotion
if psql -U postgres -c "SELECT pg_is_in_recovery();" | grep -q "f"; then
    echo "Successfully verified that node is now primary"
else
    echo "Node is still in recovery mode"
    exit 1
fi
