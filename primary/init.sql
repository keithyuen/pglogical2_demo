-- Create role only if it does not exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rep_user') THEN
        CREATE ROLE rep_user WITH REPLICATION LOGIN PASSWORD 'password';
    END IF;
END
$$;

-- Create database only if it does not exist
SELECT 'CREATE DATABASE testdb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'testdb')\gexec

\c testdb

-- Enable pglogical2 extension
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create pglogical2 node for provider
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pglogical.node WHERE node_name = 'provider_node') THEN
        PERFORM pglogical.create_node(
            node_name := 'provider_node',
            dsn := 'host=localhost port=5432 dbname=testdb user=postgres password=postgres'
        );
    END IF;
END
$$;

-- Create replication set for all tables
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pglogical.replication_set WHERE set_name = 'full_replication_set') THEN
        PERFORM pglogical.create_replication_set(
            set_name := 'full_replication_set',
            replicate_insert := true,
            replicate_update := true,
            replicate_delete := true,
            replicate_truncate := true
        );
    END IF;
END
$$;

-- Create test table if not exists
CREATE TABLE IF NOT EXISTS demo(id INT PRIMARY KEY, value TEXT);

-- Create additional test tables for comprehensive testing
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

-- Create indexes for testing
CREATE INDEX IF NOT EXISTS idx_test_table_data ON test_table(data);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);

-- Add all tables to replication set
SELECT pglogical.replication_set_add_table(
    set_name := 'full_replication_set',
    relation := 'demo',
    synchronize_data := true
);

SELECT pglogical.replication_set_add_table(
    set_name := 'full_replication_set',
    relation := 'test_table',
    synchronize_data := true
);

SELECT pglogical.replication_set_add_table(
    set_name := 'full_replication_set',
    relation := 'users',
    synchronize_data := true
);

SELECT pglogical.replication_set_add_table(
    set_name := 'full_replication_set',
    relation := 'orders',
    synchronize_data := true
);

-- Grant permissions to rep_user
GRANT ALL PRIVILEGES ON DATABASE testdb TO rep_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rep_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rep_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO rep_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO rep_user;

-- Create publication if not exists (for native logical replication comparison)
-- DO $$
-- BEGIN
--     IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'demo_pub') THEN
--         CREATE PUBLICATION demo_pub FOR ALL TABLES;
--     END IF;
-- END
-- $$;

-- Insert some test data only if not exists
INSERT INTO demo (id, value)
SELECT 1, 'Initial data from primary'
WHERE NOT EXISTS (SELECT 1 FROM demo WHERE id = 1);

INSERT INTO demo (id, value)
SELECT 2, 'More data from primary'
WHERE NOT EXISTS (SELECT 1 FROM demo WHERE id = 2);

INSERT INTO test_table (data)
SELECT 'Test data ' || generate_series(1, 5)
WHERE NOT EXISTS (SELECT 1 FROM test_table LIMIT 1);

INSERT INTO users (username, email)
SELECT 'user1', 'user1@example.com'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE username = 'user1');

-- Create replication slot for standby if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replication_slot') THEN
        PERFORM pg_create_physical_replication_slot('replication_slot', true);
    END IF;
END
$$;

