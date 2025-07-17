#!/bin/bash
set -e

# Step 1: Cleanup
./cleanup_complete.sh

# Step 2: Re-initialize cluster
sleep 2
echo "Bringing up containers..."
docker-compose up -d

echo "Cluster reset and bootstrapped." 