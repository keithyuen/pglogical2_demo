#!/bin/bash
set -e

# Configuration
PRIMARY_HOST="pg16-primary.pg-ha-env.orb.local"
PRIMARY_PORT="5432"
STANDBY_HOST="pg16-standby.pg-ha-env.orb.local"
STANDBY_PORT="5432"
SUBSCRIBER_HOST="pg16-subscriber.pg-ha-env.orb.local"
SUBSCRIBER_PORT="5432"
#PUBLICATION_NAME="test_pub"
#SUBSCRIPTION_NAME="test_sub"
TABLE_NAME="demo"

# Wait for pg16_standby to be ready
echo "Waiting for pg16_standby to be ready..."
for i in {1..30}; do
  if psql -h pg16-standby.pg-failover-slots.orb.local -U postgres -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    echo "pg16_standby is ready."
    break
  fi
  echo "Standby not ready yet, waiting..."
  sleep 2
done

echo "Test Case 1: Verifying replication slots on primary and standby"
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "SELECT * FROM pg_replication_slots;"
psql -h $STANDBY_HOST -p $STANDBY_PORT -U postgres -d testdb -c "SELECT * FROM pg_replication_slots;"
echo "Sleeping for 10 seconds after Test Case 1..."
sleep 2

# Test Case 1.1: Insert 1000 records with random IDs and verify replication
echo "Test Case 1.1: Inserting 1000 records with random IDs and verifying replication"
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "INSERT INTO demo (id, value) 
SELECT 
    (random() * 1000000)::integer, 
    'Test data ' || generate_series(1, 1000)
ON CONFLICT (id) DO NOTHING;"

# Wait for replication to complete
echo "Waiting for replication to complete..."
sleep 5

# Verify record count on both primary and subscriber
echo "Verifying record count on primary:"
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "SELECT COUNT(*) FROM demo;"
echo "Verifying record count on subscriber:"
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "SELECT COUNT(*) FROM demo;"

# Verify a sample of records on subscriber
echo "Verifying sample records on subscriber:"
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "SELECT * FROM demo ORDER BY id LIMIT 5;"
echo "Sleeping for 10 seconds after Test Case 1.1..."
sleep 10

# Test Case 2: Controlled Failover and Replication Validation

echo "Test Case 2.1: Simulate primary down (pg16_primary)"
docker stop pg16_primary
docker volume rm pg_failover_slots_pg16_primary_data  2>/dev/null || true

sleep 5
echo "Primary stopped."

echo "Test Case 2.2: Promote standby (pg16_standby) to primary"
docker exec -it pg16_standby /usr/pgsql-16/bin/pg_ctl promote -D /var/lib/pgsql/16/data
sleep 5
echo "Standby promoted."

echo "Test Case 2.3: Check if pg16_standby is now primary (should be false for recovery)"
docker exec -it pg16_standby psql -U postgres -d postgres -c "SELECT pg_is_in_recovery();"

sleep 10

echo "Test Case 2.4: Update subscription connection info on subscriber (pg16_subscriber)"
docker exec -it pg16_subscriber psql -U postgres -d testdb -c \
  "ALTER SUBSCRIPTION demo_sub CONNECTION 'host=pg16-standby.pg-failover-slots.orb.local port=5432 user=rep_user password=password dbname=testdb';"
sleep 5

# echo "Test Case 2.5: Reconfigure old primary (pg16_primary) as standby"
# docker exec -it pg16_primary pg_ctl stop -D /var/lib/pgsql/16/data -m immediate
# docker exec -it pg16_primary bash -c "rm -rf /var/lib/pgsql/16/data/*"
# docker start pg16_primary
# sleep 5
# docker exec -it pg16_primary pg_basebackup -h pg16_standby -D /var/lib/pgsql/16/data -U postgres -Fp -Xs -P -R
# sleep 5

# echo "Test Case 2.6: Confirm new primary is publishing to subscriber (pg16_subscriber)"
# docker exec -it pg16_subscriber psql -U postgres -d testdb -c "SELECT COUNT(*) FROM demo;"
# sleep 5

# echo "Test Case 2.7: Confirm new primary is publishing to new standby (old primary, pg16_primary)"
# docker exec -it pg16_primary psql -U postgres -d testdb -c "SELECT pg_is_in_recovery();"
# docker exec -it pg16_primary psql -U postgres -d testdb -c "SELECT COUNT(*) FROM demo;"
# sleep 5

# # Test Case 3: Verify replication slots on the newly promoted primary
# echo "Test Case 3: Verifying replication slots on the newly promoted primary"
# psql -h $STANDBY_HOST -p $STANDBY_PORT -U postgres -d testdb -c "SELECT * FROM pg_replication_slots;"
# echo "Sleeping for 10 seconds after Test Case 3..."
# sleep 10

# Test Case 4: Ensure downstream subscriber continues to receive changes
echo "Test Case 4: Ensuring downstream subscriber continues to receive changes"
# Insert data into the table on the newly promoted primary
psql -h $STANDBY_HOST -p $STANDBY_PORT -U postgres -d testdb -c "INSERT INTO $TABLE_NAME (name) VALUES ('test4');"
# Verify that the subscriber has received the changes
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "SELECT * FROM $TABLE_NAME;"
echo "Sleeping for 10 seconds after Test Case 4..."
sleep 10 