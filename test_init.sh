#!/bin/bash
set -e

# Run init.sql commands
psql -U postgres -d testdb -f /docker-entrypoint-initdb.d/init.sql 