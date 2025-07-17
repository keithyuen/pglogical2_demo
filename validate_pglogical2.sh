#!/bin/bash

# Validation script for pglogical2 setup
# Checks if pglogical2 is properly installed and configured

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database connection parameters (OrbStack domains)
PRIMARY_HOST="pg16-primary.pg-ha-env.orb.local"
PRIMARY_PORT="5432"
STANDBY_HOST="pg16-standby.pg-ha-env.orb.local"
STANDBY_PORT="5432"
SUBSCRIBER_HOST="pg16-subscriber.pg-ha-env.orb.local"
SUBSCRIBER_PORT="5432"
DB_NAME="testdb"
USER="postgres"
PASSWORD="postgres"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if database is accessible
check_db_connection() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking connection to $node_name ($host:$port)..."
    
    if psql -h $host -p $port -U $USER -d $DB_NAME -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "$node_name is accessible"
        return 0
    else
        print_error "$node_name is not accessible"
        return 1
    fi
}

# Function to check pglogical2 extension
check_pglogical_extension() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking pglogical2 extension on $node_name..."
    
    local ext_exists=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM pg_extension WHERE extname = 'pglogical'
        );
    ")
    
    if [ "$ext_exists" = "t" ]; then
        print_success "pglogical2 extension is installed on $node_name"
        
        # Get extension version
        local ext_version=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
            SELECT extversion FROM pg_extension WHERE extname = 'pglogical';
        ")
        print_status "pglogical2 version on $node_name: $ext_version"
    else
        print_error "pglogical2 extension is NOT installed on $node_name"
        return 1
    fi
}

# Function to check pglogical2 configuration
check_pglogical_config() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking pglogical2 configuration on $node_name..."
    
    # Check if pglogical is in shared_preload_libraries
    local shared_libs=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT setting FROM pg_settings WHERE name = 'shared_preload_libraries';
    ")
    
    if echo "$shared_libs" | grep -q "pglogical"; then
        print_success "pglogical is in shared_preload_libraries on $node_name"
    else
        print_warning "pglogical is NOT in shared_preload_libraries on $node_name"
    fi
    
    # Check other important settings
    local wal_level=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT setting FROM pg_settings WHERE name = 'wal_level';
    ")
    
    if [ "$wal_level" = "logical" ]; then
        print_success "wal_level is set to logical on $node_name"
    else
        print_error "wal_level is NOT set to logical on $node_name (current: $wal_level)"
    fi
    
    local track_commit_timestamp=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT setting FROM pg_settings WHERE name = 'track_commit_timestamp';
    ")
    
    if [ "$track_commit_timestamp" = "on" ]; then
        print_success "track_commit_timestamp is enabled on $node_name"
    else
        print_warning "track_commit_timestamp is NOT enabled on $node_name (current: $track_commit_timestamp)"
    fi
}

# Function to check pglogical2 nodes
check_pglogical_nodes() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking pglogical2 nodes on $node_name..."
    
    local node_count=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT COUNT(*) FROM pglogical.node;
    ")
    
    if [ "$node_count" -gt 0 ]; then
        print_success "Found $node_count pglogical2 node(s) on $node_name"
        
        # Show node details
        psql -h $host -p $port -U $USER -d $DB_NAME -c "
            SELECT node_name, enabled FROM pglogical.node;
        "
    else
        print_warning "No pglogical2 nodes found on $node_name"
    fi
}

# Function to check replication sets (provider only)
check_replication_sets() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking replication sets on $node_name..."
    
    local set_count=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT COUNT(*) FROM pglogical.replication_set;
    ")
    
    if [ "$set_count" -gt 0 ]; then
        print_success "Found $set_count replication set(s) on $node_name"
        
        # Show replication set details
        psql -h $host -p $port -U $USER -d $DB_NAME -c "
            SELECT set_name, replicate_insert, replicate_update, replicate_delete, replicate_truncate 
            FROM pglogical.replication_set;
        "
    else
        print_warning "No replication sets found on $node_name"
    fi
}

# Function to check subscriptions (subscriber only)
check_subscriptions() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking subscriptions on $node_name..."
    
    local sub_count=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT COUNT(*) FROM pglogical.subscription;
    ")
    
    if [ "$sub_count" -gt 0 ]; then
        print_success "Found $sub_count subscription(s) on $node_name"
        
        # Show subscription details
        psql -h $host -p $port -U $USER -d $DB_NAME -c "
            SELECT sub_name, sub_enabled, sub_conninfo FROM pglogical.subscription;
        "
    else
        print_warning "No subscriptions found on $node_name"
    fi
}

# Function to check replication status
check_replication_status() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking replication status on $node_name..."
    
    local worker_count=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT COUNT(*) FROM pg_stat_replication WHERE application_name LIKE '%pglogical%';
    ")
    
    if [ "$worker_count" -gt 0 ]; then
        print_success "Found $worker_count active pglogical2 replication worker(s) on $node_name"
        
        # Show worker details
        psql -h $host -p $port -U $USER -d $DB_NAME -c "
            SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
            FROM pg_stat_replication 
            WHERE application_name LIKE '%pglogical%';
        "
    else
        print_warning "No active pglogical2 replication workers found on $node_name"
    fi
}

# Function to check physical replication status (for standby)
check_physical_replication() {
    local host=$1
    local port=$2
    local node_name=$3
    
    print_status "Checking physical replication status on $node_name..."
    
    local replica_count=$(psql -h $host -p $port -U $USER -d $DB_NAME -t -A -c "
        SELECT COUNT(*) FROM pg_stat_replication;
    ")
    
    if [ "$replica_count" -gt 0 ]; then
        print_success "Found $replica_count active physical replication connection(s) on $node_name"
        
        # Show replication details
        psql -h $host -p $port -U $USER -d $DB_NAME -c "
            SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
            FROM pg_stat_replication;
        "
    else
        print_warning "No active physical replication connections found on $node_name"
    fi
}

# Main validation function
main() {
    print_status "Starting pglogical2 validation..."
    echo
    
    # Check database connections
    print_status "=== Database Connection Checks ==="
    check_db_connection $PRIMARY_HOST $PRIMARY_PORT "Primary"
    check_db_connection $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    check_db_connection $STANDBY_HOST $STANDBY_PORT "Standby"
    echo
    
    # Check pglogical2 extension (only on primary and subscriber)
    print_status "=== pglogical2 Extension Checks ==="
    check_pglogical_extension $PRIMARY_HOST $PRIMARY_PORT "Primary"
    check_pglogical_extension $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    print_status "Skipping pglogical2 check on Standby (uses physical replication)"
    echo
    
    # Check pglogical2 configuration (only on primary and subscriber)
    print_status "=== pglogical2 Configuration Checks ==="
    check_pglogical_config $PRIMARY_HOST $PRIMARY_PORT "Primary"
    check_pglogical_config $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    print_status "Skipping pglogical2 config check on Standby (uses physical replication)"
    echo
    
    # Check pglogical2 nodes (only on primary and subscriber)
    print_status "=== pglogical2 Node Checks ==="
    check_pglogical_nodes $PRIMARY_HOST $PRIMARY_PORT "Primary"
    check_pglogical_nodes $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    print_status "Skipping pglogical2 node check on Standby (uses physical replication)"
    echo
    
    # Check replication sets (provider)
    print_status "=== Replication Set Checks ==="
    check_replication_sets $PRIMARY_HOST $PRIMARY_PORT "Primary"
    echo
    
    # Check subscriptions (subscriber)
    print_status "=== Subscription Checks ==="
    check_subscriptions $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    echo
    
    # Check replication status
    print_status "=== Replication Status Checks ==="
    check_replication_status $PRIMARY_HOST $PRIMARY_PORT "Primary"
    check_replication_status $SUBSCRIBER_HOST $SUBSCRIBER_PORT "Subscriber"
    check_physical_replication $STANDBY_HOST $STANDBY_PORT "Standby"
    echo
    
    print_success "pglogical2 validation completed!"
    echo
    print_status "Next steps:"
    echo "1. If all checks pass, run: ./test_pglogical2.sh"
    echo "2. If there are issues, check the logs: docker-compose logs"
    echo "3. For detailed monitoring, run: psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -f monitor_pglogical2.sql"
}

# Run the main function
main "$@" 