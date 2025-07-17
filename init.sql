-- Create testdb database
-- CREATE DATABASE testdb;

-- Create testdb user
CREATE ROLE testdb WITH LOGIN PASSWORD 'testdb';

-- Connect to testdb
\c testdb

-- Create demo table
CREATE TABLE demo (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- Insert some test data
INSERT INTO demo (name) VALUES ('test1'), ('test2'), ('test3'); 