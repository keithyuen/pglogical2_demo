# pglogical2 Setup and Testing Guide

This guide covers the setup and testing of pglogical2 extension for full database replication including DDL operations across a 3-node PostgreSQL estate.

## Architecture

The setup consists of three PostgreSQL nodes:
- **Primary (Provider)**: `pg16-primary.pg-ha-env.orb.local:5432` - Source database with pglogical2 provider
- **Standby**: `pg16-standby.pg-ha-env.orb.local:5432` - Physical standby for high availability (uses streaming replication, not pglogical2)
- **Subscriber**: `pg16-subscriber.pg-ha-env.orb.local:5432` - Logical replica using pglogical2

## Prerequisites

- Docker and Docker Compose
- PostgreSQL client tools (`psql`)
- OrbStack for local development
- The pglogical2 extension is already included in the Docker image via EDB packages

## Quick Start

1. **Setup the environment:**
   ```bash
   ./setup_pglogical2.sh
   ```

2. **Start the PostgreSQL cluster:**
   ```bash
   docker-compose up -d
   ```

3. **Wait for services to be ready:**
   ```bash
   docker-compose logs -f
   ```

4. **Run the comprehensive test suite:**
   ```bash
   ./test_pglogical2.sh
   ```

## Configuration Details

### Primary Node Configuration (`primary/postgresql.conf`)

Key pglogical2 settings:
```ini
# Logical Replication settings
wal_level = logical
max_replication_slots = 10
track_commit_timestamp = on

# Shared libraries
shared_preload_libraries = 'pg_failover_slots,pg_stat_statements,pglogical'

# pglogical2 settings
pglogical.conflict_resolution = 'last_update_wins'
pglogical.use_spi = on
```

### Subscriber Node Configuration (`subscriber/postgresql.conf`)

Similar configuration with pglogical2 enabled:
```ini
# Shared libraries
shared_preload_libraries = 'pglogical'

# pglogical2 settings
pglogical.conflict_resolution = 'last_update_wins'
pglogical.use_spi = on
```

### Standby Node Configuration (`standby/postgresql.conf`)

Physical standby configuration (no pglogical2):
```ini
# Standby settings
hot_standby = on
hot_standby_feedback = on
wal_log_hints = on
primary_conninfo = 'host=pg16_primary port=5432 user=postgres password=postgres application_name=pg16_standby'

# Shared libraries (only pg_failover_slots for physical standby)
shared_preload_libraries = 'pg_failover_slots'
```

## pglogical2 Setup

### Provider Setup (Primary)

The primary node is configured as a pglogical2 provider with:

1. **Node Creation:**
   ```sql
   SELECT pglogical.create_node(
       node_name := 'provider_node',
       dsn := 'host=pg16_primary port=5432 dbname=testdb user=postgres password=postgres'
   );
   ```

2. **Replication Set:**
   ```sql
   SELECT pglogical.create_replication_set(
       set_name := 'full_replication_set',
       replicate_insert := true,
       replicate_update := true,
       replicate_delete := true,
       replicate_truncate := true
   );
   ```

3. **Table Addition:**
   ```sql
   SELECT pglogical.replication_set_add_table(
       set_name := 'full_replication_set',
       relation := 'table_name',
       synchronize_data := true
   );
   ```

### Subscriber Setup

The subscriber node is configured with:

1. **Node Creation:**
   ```sql
   SELECT pglogical.create_node(
       node_name := 'subscriber_node',
       dsn := 'host=pg16_subscriber port=5432 dbname=testdb user=postgres password=postgres'
   );
   ```

2. **Subscription:**
   ```sql
   SELECT pglogical.create_subscription(
       subscription_name := 'provider_subscription',
       provider_dsn := 'host=pg16_primary port=5432 dbname=testdb user=postgres password=postgres',
       replication_sets := ARRAY['full_replication_set'],
       synchronize_data := true,
       forward_origins := '{}'
   );
   ```

## DDL Replication

pglogical2 supports DDL replication using the `pglogical.replicate_ddl_command()` function:

```sql
-- Example: Create a new table
SELECT pglogical.replicate_ddl_command('
    CREATE TABLE new_table (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100)
    );
');

-- Example: Add a column
SELECT pglogical.replicate_ddl_command('
    ALTER TABLE existing_table ADD COLUMN new_column VARCHAR(50);
');

-- Example: Create an index
SELECT pglogical.replicate_ddl_command('
    CREATE INDEX idx_new_column ON existing_table(new_column);
');
```

## Testing

The test suite (`test_pglogical2.sh`) covers:

### 1. Basic Data Replication
- INSERT operations
- UPDATE operations  
- DELETE operations
- Data consistency verification

### 2. DDL Replication
- CREATE TABLE operations
- ALTER TABLE operations (add columns)
- CREATE INDEX operations
- CREATE VIEW operations
- DROP TABLE operations

### 3. Performance Testing
- Bulk insert operations
- Replication lag monitoring
- Conflict resolution testing

### 4. Monitoring
- Replication status checks
- Lag monitoring
- Error detection

## Monitoring and Troubleshooting

### Status Monitoring

Use the monitoring script to check pglogical2 status:

```bash
# Check provider status
psql -h pg16-primary.pg-ha-env.orb.local -p 5432 -U postgres -d testdb -f monitor_pglogical2.sql

# Check subscriber status  
psql -h pg16-subscriber.pg-ha-env.orb.local -p 5432 -U postgres -d testdb -f monitor_pglogical2.sql
```