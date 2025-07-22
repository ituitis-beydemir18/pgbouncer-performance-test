#!/bin/bash

# Direct PostgreSQL Connection Test Script
# Tests performance and connectivity directly to PostgreSQL

set -e

# Source environment variables (if running on test client)
if [ -f "/home/ubuntu/.env" ]; then
    source /home/ubuntu/.env
fi

# Configuration - override these with environment variables
DB_HOST=${DB_HOST:-"your-rds-endpoint.amazonaws.com"}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-"testdb"}
DB_USERNAME=${DB_USERNAME:-"postgres"}
DB_PASSWORD=${DB_PASSWORD:-"your-password"}

# Set password for PostgreSQL commands
export PGPASSWORD="$DB_PASSWORD"

echo "======================================"
echo "Direct PostgreSQL Connection Test"
echo "======================================"
echo "Testing direct connection to PostgreSQL database"
echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"
echo "User: $DB_USERNAME"
echo ""

# Test 1: Basic Connectivity
echo "Test 1: Basic Connectivity"
echo "=========================="
echo "Testing basic database connection..."

if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();" 2>/dev/null; then
    echo "✅ Connection successful!"
else
    echo "❌ Connection failed!"
    echo "Please check:"
    echo "  - Database host and port"
    echo "  - Username and password"
    echo "  - Network connectivity"
    echo "  - Security groups/firewall"
    exit 1
fi

echo ""

# Test 2: Connection Timing
echo "Test 2: Connection Timing"
echo "========================"
echo "Measuring connection establishment time..."

echo "Single connection time:"
time psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null

echo ""

# Test 3: Multiple Connection Test
echo "Test 3: Multiple Connection Test"
echo "==============================="
echo "Testing 10 sequential connections (shows connection overhead)..."

start_time=$(date +%s.%N)
for i in {1..10}; do
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT $i;" > /dev/null
done
end_time=$(date +%s.%N)

total_time=$(echo "$end_time - $start_time" | bc -l)
avg_time=$(echo "scale=3; $total_time / 10" | bc -l)

echo "10 connections completed in ${total_time}s"
echo "Average time per connection: ${avg_time}s"
echo ""

# Test 4: Database Information
echo "Test 4: Database Information"
echo "==========================="
echo "Gathering database information..."

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" << 'EOF'
\echo 'PostgreSQL Version:'
SELECT version();

\echo ''
\echo 'Database Size:'
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

\echo ''
\echo 'Connection Limits:'
SHOW max_connections;

\echo ''
\echo 'Current Connections:'
SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';

\echo ''
\echo 'Available Tables:'
\dt

\echo ''
\echo 'Sample Data Count (if pgbench tables exist):'
SELECT 
    'pgbench_accounts' as table_name, count(*) as row_count
FROM pgbench_accounts
UNION ALL
SELECT 
    'pgbench_branches' as table_name, count(*) as row_count
FROM pgbench_branches
UNION ALL
SELECT 
    'pgbench_tellers' as table_name, count(*) as row_count
FROM pgbench_tellers
ORDER BY table_name;
EOF

echo ""

# Test 5: Simple Performance Test
echo "Test 5: Simple Performance Test"
echo "=============================="
echo "Running a simple pgbench test (5 clients, 20 transactions each)..."
echo "This gives baseline performance for direct connections."

pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 5 -j 5 -t 20 -n --report-latencies

echo ""

# Test 6: Connection Limit Test
echo "Test 6: Connection Limit Test"
echo "============================"
echo "Testing what happens when we approach connection limits..."
echo "Running 50 concurrent connections (may succeed or fail depending on load)..."

if pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 50 -j 25 -t 5 -n --report-latencies 2>/dev/null; then
    echo "✅ 50 concurrent connections succeeded"
else
    echo "❌ 50 concurrent connections failed (possibly due to connection limits)"
fi

echo ""

# Summary
echo "======================================"
echo "Direct Connection Test Summary"
echo "======================================"
echo "✅ Basic connectivity: Working"
echo "📊 Connection overhead: ~${avg_time}s per connection"
echo "🔗 Concurrent connections: Limited by max_connections setting"
echo ""
echo "Key Observations:"
echo "- Each connection requires authentication and session setup"
echo "- Connection establishment has measurable overhead"
echo "- High concurrency is limited by database connection limits"
echo "- Direct connections work well for low-concurrency applications"
echo ""
echo "💡 Compare these results with PgBouncer to see the benefits of connection pooling!"
echo "======================================" 