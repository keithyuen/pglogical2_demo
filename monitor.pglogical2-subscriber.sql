-- Test 1: Basic data replication
select * from demo where id = '102';

select * from users where username = 'testuser2';

-- Test 1.1: Conflict resolution
select * from public.conflict_test;

-- Test 2: DDL Replication - Add New Table ddl_test_table1
SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'ddl_test_table1'
        );

select * from ddl_test_table1;

-- Test 3 / 4: Add column new_column1
SELECT * FROM test_table;

SELECT * FROM test_table WHERE id = 2;

-- Test 5: Create index
SELECT EXISTS (
            SELECT FROM pg_indexes 
            WHERE tablename = 'test_table' AND indexname = 'idx_test_table_new_column1'
        );

-- Test 6: Create view
SELECT EXISTS (
            SELECT FROM information_schema.views 
            WHERE table_name = 'test_view1'
        );
		
select * from test_view1;



-- MONITORING
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

select * FROM pglogical.subscription;

-- refresh subscription if inactive
SELECT pglogical.alter_subscription_enable('provider_subscription', true);

-- 7. Check replication workers (Primary)
SELECT *
FROM pg_stat_replication;

WHERE application_name LIKE '%pglogical%';

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