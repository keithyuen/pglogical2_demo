-- Test Case 1: Verify replication slots on primary
\echo 'Test Case 1: Verifying replication slots on primary'
SELECT * FROM pg_replication_slots;

-- Test Case 1.1: Insert 1000 records with random IDs and verify replication
\echo 'Test Case 1.1: Inserting 1000 records with random IDs'
INSERT INTO demo (id, value)
SELECT (random() * 1000000)::integer, 'Test data ' || generate_series(1, 1000)
ON CONFLICT (id) DO NOTHING;

-- Wait for replication to complete (manual: sleep or just run the next query after a short pause)
\echo 'Verifying record count on primary:'
SELECT COUNT(*) FROM demo;

-- Verifying sample records on primary
\echo 'Verifying sample records on primary:'
SELECT * FROM demo ORDER BY id LIMIT 5;

-- If you want to check on the subscriber, run this script with psql against the subscriber host/port:
-- \echo 'Verifying record count on subscriber:'
-- SELECT COUNT(*) FROM demo;
-- \echo 'Verifying sample records on subscriber:'
-- SELECT * FROM demo ORDER BY id LIMIT 5;

-- You can also check replication slots on the standby (if running against standby):
-- \echo 'Verifying replication slots on standby:'
-- SELECT * FROM pg_replication_slots;

-- For failover and promotion, you would need to run shell commands (not possible in pure SQL).
-- You can, however, check if the server is in recovery mode:
\echo 'Checking if this server is in recovery mode:'
SELECT pg_is_in_recovery();

-- To check logical replication status:
\echo 'Checking logical replication status:'
SELECT * FROM pg_stat_subscription;

-- To check WAL receiver status (on standby):
\echo 'Checking WAL receiver status:'
SELECT * FROM pg_stat_wal_receiver; 