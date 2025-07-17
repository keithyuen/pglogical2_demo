-- Failover slots
SELECT * FROM pg_replication_slots;

-- Test 1: Basic data replication
INSERT INTO demo (id, value) VALUES (102, 'Test data from pgadmin');

select * from demo where id = 102;

INSERT INTO users (username, email) VALUES ('testuser2', 'test2@example.com');

select * from users where username = 'testuser2';

-- Test 1.1: Conflict resolution
select * from conflict_test;

SELECT pglogical.replication_set_add_table(
            set_name := 'full_replication_set',
            relation := 'conflict_test',
            synchronize_data := true
        );

-- Test 2: DDL Replication - Add New Table ddl_test_table1
SELECT pglogical.replicate_ddl_command('
            CREATE TABLE public.ddl_test_table1 (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100),
                description TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX idx_ddl_test_name1 ON public.ddl_test_table1(name);
        ', ARRAY['full_replication_set']);

-- Test 3: DDL Replication - Add column new_column1
SELECT pglogical.replicate_ddl_command('
            ALTER TABLE public.test_table 
			ADD COLUMN new_column1 VARCHAR(50) DEFAULT ''default_value'';
        ', ARRAY['full_replication_set']);

SELECT * FROM test_table;

-- Test 4: Data operations on new column
UPDATE test_table SET new_column1 = 'updated_value2' WHERE id = 2;

INSERT INTO test_table (data, new_column1) VALUES ('Data with new column1', 'custom_value2');

-- Test 5: DDL Replication - Create Index
SELECT pglogical.replicate_ddl_command('
            CREATE INDEX idx_test_table_new_column1 ON public.test_table(new_column1);
        ', ARRAY['full_replication_set']);

-- Test 6: DDL - Create view
SELECT pglogical.replicate_ddl_command('
            CREATE VIEW public.test_view1 AS 
            SELECT t.id, t.data, t.new_column1, u.username 
            FROM public.test_table t 
            LEFT JOIN public.users u ON t.id = u.user_id;
        ', ARRAY['full_replication_set']);

SELECT set_name, replicate_insert, replicate_update, replicate_delete, replicate_truncate 
        FROM pglogical.replication_set;

-- pglogical2 Monitoring and Troubleshooting Script
-- Run this on both provider and subscriber nodes

-- 1. Check pglogical2 extension status
SELECT 
    extname,
    extversion,
    extrelocatable
FROM pg_extension 
WHERE extname = 'pglogical';

-- 2. Check pglogical2 nodes
SELECT * FROM pglogical.node;

-- 3. Check replication sets
SELECT * FROM pglogical.replication_set;

-- 4. Check tables in replication sets (primary)
select * FROM pglogical.replication_set_table;

-- 5. Check subscriptions (run on subscriber)
SELECT * FROM pglogical.subscription;

-- 6. Check subscription status and lag
select sub_id, sub_name, sub_slot_name, sub_replication_sets, sub_apply_delay
FROM pglogical.subscription;

-- 7. Check replication workers (Primary)
SELECT *
FROM pg_stat_replication;

WHERE application_name LIKE '%pglogical%';

-- 8. Check for replication conflicts
select * FROM pg_stat_database_conflicts
--WHERE confl_tablespace > 0 
--   OR confl_lock > 0 
--   OR confl_snapshot > 0 
--   OR confl_bufferpin > 0 
--   OR confl_deadlock > 0;

-- 9. Check WAL configurations
SELECT 
    name,
    setting,
    unit,
    context
FROM pg_settings 
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'track_commit_timestamp',
    'wal_keep_size',
    'max_slot_wal_keep_size'
);

-- 10. Check replication slots (Primary)
SELECT 
    slot_name,
    plugin,
    slot_type,
    database,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag_size
FROM pg_replication_slots
WHERE slot_name LIKE 'pgl%';


-- 16. Check for any long-running transactions that might block replication
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    backend_start,
    state,
    state_change,
    query_start,
    EXTRACT(EPOCH FROM (now() - query_start)) as duration_seconds
FROM pg_stat_activity
WHERE state = 'active' 
  AND query_start < now() - interval '5 minutes'
  AND query NOT LIKE '%pg_stat_activity%';

-- 17. Check for any replication slots that might be causing issues (Primary)
SELECT 
    slot_name,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as lag_bytes,
    CASE 
        WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 1073741824 THEN 'HIGH LAG'
        WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 104857600 THEN 'MEDIUM LAG'
        ELSE 'LOW LAG'
    END as lag_status
FROM pg_replication_slots
WHERE slot_name LIKE '%pglogical%';

-- 18. Check for any tables that might be causing replication issues
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'public'
  AND tablename IN ('demo', 'test_table', 'users', 'orders')
ORDER BY tablename, attname;

-- 19. Check for any indexes that might be affecting replication performance
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN ('demo', 'test_table', 'users', 'orders')
ORDER BY tablename, indexname;

-- 20. Summary report
SELECT 
    'pglogical2 Status Summary' as report_type,
    (SELECT COUNT(*) FROM pglogical.node) as total_nodes,
    (SELECT COUNT(*) FROM pglogical.replication_set) as total_replication_sets,
    (SELECT COUNT(*) FROM pglogical.subscription) as total_subscriptions,
    (SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name LIKE '%pglogical%') as total_replication_slots,
    (SELECT COUNT(*) FROM pg_stat_replication WHERE application_name LIKE '%pglogical%') as active_replication_workers; 