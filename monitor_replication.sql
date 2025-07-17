
-- REF: https://knowledge.enterprisedb.com/hc/en-us/articles/15476053320092-Monitoring-streaming-replication-in-PostgreSQL 

-- CHECK PRIMARY - STREAMING REPLICATION
-- pg_stat_replication view contains one row per WAL sender process, showing statistics about replication to that sender's connected standby server. 
-- The lag times reported in this view measure the time taken for recent WAL (Write-Ahead Log) to be written, flushed, replayed, and acknowledged by the sender.

SELECT * FROM pg_stat_replication;

SELECT * FROM pg_replication_slots;

INSERT INTO demo (id, value) 
SELECT 
    (random() * 1000000)::integer, 
    'Test data ' || generate_series(1, 1000)
ON CONFLICT (id) DO NOTHING;

select count(*) from demo;

-- CHECK STANDBY - STREAMING REPLICATION
-- pg_stat_wal_receiver view displays information about the server's WAL receiver. It contains only one row, showing statistics about the WAL receiver from that receiver's connected server.

SELECT * FROM pg_stat_wal_receiver;

SELECT * FROM pg_replication_slots;

-- pg_is_in_recovery() function can be used to check whether a standby server is in recovery mode or not.
SELECT pg_is_in_recovery();

-- CHECK: Lag in Bytes
SELECT client_addr, 
       pg_wal_lsn_diff(pg_stat_replication.sent_lsn, pg_stat_replication.replay_lsn) AS byte_lag 
FROM pg_stat_replication;

-- CHECK: Lag in Seconds
SELECT CASE 
           WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 
           ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
       END AS log_delay;

-- pg_last_wal_receive_lsn() - Returns the last write-ahead log location that has been received and synced to disk by streaming replication. 
-- CHECK: If recovery has been completed, this remains static at the location of the last WAL record received and synced to disk during recovery. If streaming replication is disabled, or if it has not yet started, the function returns NULL.
SELECT pg_last_wal_receive_lsn();

-- pg_last_wal_replay_lsn() - Returns the last write-ahead log location that has been replayed during recovery. If recovery is still in progress, this increases monotonically. If recovery has been completed, this remains static at the location of the last WAL record applied. When the server has been started normally without recovery, the function returns NULL.
SELECT pg_last_wal_replay_lsn();

-- CHECK SUBSCRIBER - LOGICAL REPLICATION
select * from pg_subscription;

-- Check publisher On Primary
select * from pg_publication;
select * from pg_publication_tables;


