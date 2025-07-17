#!/bin/bash

# Setup script for pglogical2 testing environment

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_status "Setting up pglogical2 testing environment..."

# Make test script executable
chmod +x test_pglogical2.sh

print_success "Made test_pglogical2.sh executable"

# Check if PostgreSQL client is available
if ! command -v psql &> /dev/null; then
    print_warning "PostgreSQL client (psql) not found in PATH"
    print_warning "Please install PostgreSQL client tools to run the tests"
    print_warning "On macOS: brew install postgresql"
    print_warning "On Ubuntu/Debian: sudo apt-get install postgresql-client"
    print_warning "On CentOS/RHEL: sudo yum install postgresql"
fi

print_status "pglogical2 testing environment setup complete!"
echo
print_status "Next steps:"
echo "1. Start the PostgreSQL cluster:"
echo "   docker-compose up -d"
echo
echo "2. Wait for all services to be ready (check logs):"
echo "   docker-compose logs -f"
echo
echo "3. Run the pglogical2 test suite:"
echo "   ./test_pglogical2.sh"
echo
echo "4. Monitor pglogical2 status:"
echo "   psql -h pg16-primary.pg-ha-env.orb.local -p 5432 -U postgres -d testdb -f monitor_pglogical2.sql"
echo "   psql -h pg16-subscriber.pg-ha-env.orb.local -p 5432 -U postgres -d testdb -f monitor_pglogical2.sql"
echo
print_status "Test coverage includes:"
echo "- Basic data replication (INSERT, UPDATE, DELETE)"
echo "- DDL replication (CREATE TABLE, ALTER TABLE, CREATE INDEX, DROP TABLE)"
echo "- View creation and replication"
echo "- Bulk operations performance"
echo "- Replication lag monitoring"
echo "- Conflict resolution testing"
echo
print_status "Architecture:"
echo "- Primary (Provider): pg16-primary.pg-ha-env.orb.local:5432"
echo "- Standby (Physical): pg16-standby.pg-ha-env.orb.local:5432"
echo "- Subscriber (Logical): pg16-subscriber.pg-ha-env.orb.local:5432"
echo
print_status "Note: Standby uses physical streaming replication (not pglogical2)"
echo
print_status "For more information about pglogical2, visit:"
echo "https://github.com/2ndQuadrant/pglogical" 