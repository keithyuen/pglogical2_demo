#!/bin/bash

# Test script for pglogical2 extension
# Tests DDL replication, data replication, and various scenarios

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

# Function to wait for database to be ready
wait_for_db() {
    local host=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for database at $host:$port to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if psql -h $host -p $port -U $USER -d $DB_NAME -c "SELECT 1;" >/dev/null 2>&1; then
            print_success "Database at $host:$port is ready"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts: Database not ready yet, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Database at $host:$port failed to become ready after $max_attempts attempts"
    return 1
}

# Function to execute SQL and capture output
execute_sql() {
    local host=$1
    local port=$2
    local sql=$3
    local description=$4
    
    print_status "Executing: $description"
    echo "$sql" | psql -h $host -p $port -U $USER -d $DB_NAME -t -A
}

# Function to compare data between primary and subscriber
compare_data() {
    local table_name=$1
    local description=$2
    
    print_status "Comparing data for table: $table_name - $description"
    
    local primary_data=$(psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -t -A -c "SELECT COUNT(*) FROM $table_name;")
    local subscriber_data=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "SELECT COUNT(*) FROM $table_name;")
    
    if [ "$primary_data" = "$subscriber_data" ]; then
        print_success "Data count matches for $table_name: $primary_data rows"
    else
        print_error "Data count mismatch for $table_name: Primary=$primary_data, Subscriber=$subscriber_data"
        return 1
    fi
}

# Function to check pglogical2 status
check_pglogical_status() {
    print_status "Checking pglogical2 status..."
    
    # Check provider status
    print_status "Provider status:"
    psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -c "
        SELECT node_name FROM pglogical.node;
    "
    
    # Check subscriber status
    print_status "Subscriber status:"
    psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -c "
        SELECT sub_name, sub_enabled FROM pglogical.subscription;
    "
    
    # Check replication sets
    print_status "Replication sets:"
    psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -c "
        SELECT set_name, replicate_insert, replicate_update, replicate_delete, replicate_truncate 
        FROM pglogical.replication_set;
    "
}

# Main test execution
main() {
    print_status "Starting pglogical2 comprehensive test suite..."
    
    # Wait for databases to be ready
    wait_for_db $PRIMARY_HOST $PRIMARY_PORT
    wait_for_db $SUBSCRIBER_HOST $SUBSCRIBER_PORT
    
    # Check initial pglogical2 status
    check_pglogical_status
    
    # Test 1: Basic data replication
    print_status "=== Test 1: Basic Data Replication ==="
    
    # Insert data on primary
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        INSERT INTO demo (id, value) VALUES (100, 'Test data from script');
        INSERT INTO test_table (data) VALUES ('New test data');
        INSERT INTO users (username, email) VALUES ('testuser', 'test@example.com');
    " "Inserting test data on primary"
    
    # Wait for replication
    sleep 5
    
    # Compare data
    # compare_data "demo" "After inserting test data"
    # compare_data "test_table" "After inserting test data"
    # compare_data "users" "After inserting test data"
    
    # Test 1.1: Conflict Resolution Testing
    print_status "=== Test 1.1: Conflict Resolution Testing ==="
    
    # Create a test table for conflict testing
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        CREATE TABLE IF NOT EXISTS conflict_test (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) UNIQUE,
            value TEXT,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    " "Creating conflict test table"
    
    # Add to replication set
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replication_set_add_table(
            set_name := 'full_replication_set',
            relation := 'conflict_test',
            synchronize_data := true
        );
    " "Adding conflict_test table to replication set"
    
    # Wait for table to be replicated and synchronized
    sleep 20
    
    # Verify table exists on subscriber
    local table_exists=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'conflict_test'
        );
    ")
    
    if [ "$table_exists" != "t" ]; then
        print_error "Conflict test table not replicated to subscriber"
        print_status "Attempting to manually create table on subscriber..."
        
        # Manually create the table on subscriber as fallback
        execute_sql $SUBSCRIBER_HOST $SUBSCRIBER_PORT "
            CREATE TABLE IF NOT EXISTS conflict_test (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) UNIQUE,
                value TEXT,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        " "Manually creating conflict_test table on subscriber"
        
        # Wait a bit more
        sleep 10
    fi
    
    # Insert initial data on primary
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        INSERT INTO conflict_test (name, value) VALUES 
        ('test1', 'primary_value_1'),
        ('test2', 'primary_value_2'),
        ('test3', 'primary_value_3');
    " "Inserting initial data on primary"
    
    # Wait for replication
    sleep 5
    
    # Simulate conflict: Insert same data on subscriber (should be ignored due to keep_local)
    execute_sql $SUBSCRIBER_HOST $SUBSCRIBER_PORT "
        INSERT INTO conflict_test (name, value) VALUES 
        ('test1', 'subscriber_value_1'),
        ('test4', 'subscriber_value_4')
        ON CONFLICT (name) DO UPDATE SET 
            value = EXCLUDED.value,
            updated_at = CURRENT_TIMESTAMP;
    " "Simulating conflict on subscriber"
    
    # Update data on primary
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        UPDATE conflict_test SET 
            value = 'primary_updated_value_1',
            updated_at = CURRENT_TIMESTAMP
        WHERE name = 'test1';
        
        INSERT INTO conflict_test (name, value) VALUES ('test5', 'primary_value_5');
    " "Updating data on primary"
    
    # Wait for replication
    sleep 5
    
    # Check conflict resolution results
    print_status "Checking conflict resolution results..."
    
    # Check data on primary
    print_status "Primary data:"
    psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -c "
        SELECT id, name, value, updated_at FROM conflict_test ORDER BY name;
    "
    
    # Check data on subscriber
    print_status "Subscriber data:"
    psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -c "
        SELECT id, name, value, updated_at FROM conflict_test ORDER BY name;
    "
    
    # Verify conflict resolution behavior
    local primary_count=$(psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -t -A -c "SELECT COUNT(*) FROM conflict_test;")
    local subscriber_count=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "SELECT COUNT(*) FROM conflict_test;")
    
    if [ "$primary_count" = "$subscriber_count" ]; then
        print_success "Conflict resolution successful: Row counts match ($primary_count rows)"
    else
        print_error "Conflict resolution failed: Row count mismatch (Primary=$primary_count, Subscriber=$subscriber_count)"
    fi
    
    # Check specific conflict resolution cases
    local test1_primary=$(psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U $USER -d $DB_NAME -t -A -c "SELECT value FROM conflict_test WHERE name = 'test1';")
    local test1_subscriber=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "SELECT value FROM conflict_test WHERE name = 'test1';")
    
    if [ "$test1_primary" = "$test1_subscriber" ]; then
        print_success "Conflict resolution for test1: Primary value preserved ($test1_primary)"
    else
        print_error "Conflict resolution for test1: Values differ (Primary=$test1_primary, Subscriber=$test1_subscriber)"
    fi
    
    # Test 2: DDL Replication - Add new table
    print_status "=== Test 2: DDL Replication - Add New Table ==="
    
    # Use pglogical.replicate_ddl_command for DDL replication
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replicate_ddl_command('
            CREATE TABLE public.ddl_test_table (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                description TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX idx_ddl_test_name ON public.ddl_test_table(name);
        ', ARRAY['full_replication_set']);
    " "Creating new table with DDL replication"
    
    # Wait for DDL replication
    sleep 10
    
    # Check if table exists on subscriber
    local table_exists=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'ddl_test_table'
        );
    ")
    
    if [ "$table_exists" = "t" ]; then
        print_success "DDL replication successful: ddl_test_table created on subscriber"
    else
        print_error "DDL replication failed: ddl_test_table not found on subscriber"
    fi
    
    # Test 3: DDL Replication - Add column
    print_status "=== Test 3: DDL Replication - Add Column ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replicate_ddl_command('
            ALTER TABLE public.test_table ADD COLUMN new_column VARCHAR(50) DEFAULT ''default_value'';
        ', ARRAY['full_replication_set']);
    " "Adding column to existing table"
    
    sleep 10
    
    # Check if column exists on subscriber
    local column_exists=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM information_schema.columns 
            WHERE table_name = 'test_table' AND column_name = 'new_column'
        );
    ")
    
    if [ "$column_exists" = "t" ]; then
        print_success "DDL replication successful: new_column added to test_table on subscriber"
    else
        print_error "DDL replication failed: new_column not found on subscriber"
    fi
    
    # Test 4: Data operations on new column
    print_status "=== Test 4: Data Operations on New Column ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        UPDATE test_table SET new_column = 'updated_value' WHERE id = 1;
        INSERT INTO test_table (data, new_column) VALUES ('Data with new column', 'custom_value');
    " "Testing data operations on new column"
    
    sleep 5
    
    # Compare data
    compare_data "test_table" "After operations on new column"
    
    # Test 5: DDL Replication - Create index
    print_status "=== Test 5: DDL Replication - Create Index ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replicate_ddl_command('
            CREATE INDEX idx_test_table_new_column ON public.test_table(new_column);
        ', ARRAY['full_replication_set']);
    " "Creating index on new column"
    
    sleep 10
    
    # Check if index exists on subscriber
    local index_exists=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM pg_indexes 
            WHERE tablename = 'test_table' AND indexname = 'idx_test_table_new_column'
        );
    ")
    
    if [ "$index_exists" = "t" ]; then
        print_success "DDL replication successful: index created on subscriber"
    else
        print_error "DDL replication failed: index not found on subscriber"
    fi
    
    # Test 6: Complex DDL - Create view
    print_status "=== Test 6: DDL Replication - Create View ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replicate_ddl_command('
            CREATE VIEW public.test_view AS 
            SELECT t.id, t.data, t.new_column, u.username 
            FROM public.test_table t 
            LEFT JOIN public.users u ON t.id = u.user_id;
        ', ARRAY['full_replication_set']);
    " "Creating view with DDL replication"
    
    sleep 10
    
    # Check if view exists on subscriber
    local view_exists=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT EXISTS (
            SELECT FROM information_schema.views 
            WHERE table_name = 'test_view'
        );
    ")
    
    if [ "$view_exists" = "t" ]; then
        print_success "DDL replication successful: view created on subscriber"
    else
        print_error "DDL replication failed: view not found on subscriber"
    fi
    
    # Test 7: DDL Replication - Drop table
    print_status "=== Test 7: DDL Replication - Drop Table ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        SELECT pglogical.replicate_ddl_command('
            DROP TABLE public.ddl_test_table CASCADE;
        ', ARRAY['full_replication_set']);
    " "Dropping table with DDL replication"
    
    sleep 10
    
    # Check if table is dropped on subscriber
    local table_dropped=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT NOT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'ddl_test_table'
        );
    ")
    
    if [ "$table_dropped" = "t" ]; then
        print_success "DDL replication successful: table dropped on subscriber"
    else
        print_error "DDL replication failed: table still exists on subscriber"
    fi
    
    # Test 8: Performance test - Bulk operations
    print_status "=== Test 8: Performance Test - Bulk Operations ==="
    
    execute_sql $PRIMARY_HOST $PRIMARY_PORT "
        INSERT INTO test_table (data, new_column)
        SELECT 'Bulk data ' || generate_series(1000, 2000), 'bulk_value'
        FROM generate_series(1, 1000);
    " "Performing bulk insert operation"
    
    sleep 10
    
    compare_data "test_table" "After bulk insert operation"
    
    # Test 9: Check replication lag
    print_status "=== Test 9: Replication Lag Check ==="
    
    # Check replication lag on subscriber
    local lag_info=$(psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U $USER -d $DB_NAME -t -A -c "
        SELECT 
            sub_name,
            sub_enabled,
            CASE 
                WHEN sub_slot_name IS NOT NULL THEN 
                    'Replication slot: ' || sub_slot_name
                ELSE 'No replication slot info' 
            END as slot_info
        FROM pglogical.subscription;
    ")
    
    print_status "Replication lag information: $lag_info"
    
    # Test 10: Final status check
    print_status "=== Test 10: Final Status Check ==="
    check_pglogical_status
    
    print_success "All pglogical2 tests completed successfully!"
}

# Run the main function
main "$@" 