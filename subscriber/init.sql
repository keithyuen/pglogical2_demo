-- Create database only if it does not exist
SELECT 'CREATE DATABASE testdb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'testdb')\gexec
\c testdb

-- Enable pglogical2 extension
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create pglogical2 node for subscriber
SELECT pglogical.create_node(
    node_name := 'subscriber_node',
    dsn := 'host=localhost port=5432 dbname=testdb user=postgres password=postgres'
);

-- Create the same tables structure as provider (for initial sync)
CREATE TABLE IF NOT EXISTS demo(id INT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS test_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'pending'
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_test_table_data ON test_table(data);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);

-- Create subscription to provider
SELECT pglogical.create_subscription(
    subscription_name := 'provider_subscription',
    provider_dsn := 'host=pg16-primary.pg-ha-env.orb.local port=5432 dbname=testdb user=postgres password=postgres',
    replication_sets := ARRAY['full_replication_set'],
    synchronize_data := true,
    forward_origins := '{}'
);

-- Also create native logical replication subscription for comparison
-- CREATE SUBSCRIPTION demo_sub
--   CONNECTION 'host=pg16-primary.pg-ha-env.orb.local port=5432 user=rep_user password=password dbname=testdb'
--   PUBLICATION demo_pub
--   WITH (copy_data = true);
