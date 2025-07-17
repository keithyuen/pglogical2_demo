# Setup replication
echo "Setting up replication (if not already setup)..."
# Create table on primary
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "CREATE TABLE IF NOT EXISTS $TABLE_NAME (id SERIAL PRIMARY KEY, name TEXT);"
# Create table on subscriber
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "CREATE TABLE IF NOT EXISTS $TABLE_NAME (id SERIAL PRIMARY KEY, name TEXT);"
# Create table on standby
psql -h $STANDBY_HOST -p $STANDBY_PORT -U postgres -d testdb -c "CREATE TABLE IF NOT EXISTS $TABLE_NAME (id SERIAL PRIMARY KEY, name TEXT);"
# Create publication
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "DROP PUBLICATION IF EXISTS $PUBLICATION_NAME;"
psql -h $PRIMARY_HOST -p $PRIMARY_PORT -U postgres -d testdb -c "CREATE PUBLICATION $PUBLICATION_NAME FOR TABLE $TABLE_NAME;"
# Create subscription
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "DROP SUBSCRIPTION IF EXISTS $SUBSCRIPTION_NAME;"
psql -h $SUBSCRIBER_HOST -p $SUBSCRIBER_PORT -U postgres -d testdb -c "CREATE SUBSCRIPTION $SUBSCRIPTION_NAME CONNECTION 'host=$PRIMARY_HOST port=$PRIMARY_PORT dbname=testdb user=postgres' PUBLICATION $PUBLICATION_NAME;"