#!/bin/bash

# PgBouncer Performance Comparison Test
# This script runs comprehensive performance tests comparing direct vs pooled connections

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
PGBOUNCER_HOST=${PGBOUNCER_HOST:-"your-pgbouncer-host"}
PGBOUNCER_PORT=${PGBOUNCER_PORT:-6432}

# Set password for PostgreSQL commands
export PGPASSWORD="$DB_PASSWORD"

# Results directory
RESULTS_DIR="${HOME}/test_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

# Cleanup function to reset state between tests
cleanup_between_tests() {
    local test_name="$1"
    echo ""
    echo "🧹 Cleaning up after $test_name..."
    echo "   This ensures fair comparison by resetting database and system state"
    
    # 1. Reset PostgreSQL statistics
    echo "   ⏳ Resetting database statistics..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
        -c "SELECT pg_stat_reset();" > /dev/null 2>&1 || echo "   ⚠️  Database stats reset failed (non-critical)"
    
    # 2. Reset PgBouncer pools
    echo "   ⏳ Resetting PgBouncer connection pools..."
    psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d pgbouncer \
        -c "PAUSE;" > /dev/null 2>&1 || echo "   ⚠️  PgBouncer pause failed (non-critical)"
    sleep 3
    psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d pgbouncer \
        -c "RESUME;" > /dev/null 2>&1 || echo "   ⚠️  PgBouncer resume failed (non-critical)"
    
    # 3. Clear OS caches (attempt)
    echo "   ⏳ Attempting to clear OS caches..."
    sync > /dev/null 2>&1
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' > /dev/null 2>&1 || echo "   ⚠️  OS cache clear failed (requires sudo - non-critical)"
    
    # 4. Wait for TCP connections to settle
    echo "   ⏳ Waiting for TCP connections to settle..."
    sleep 15
    
    # 5. Show current connection state
    DIRECT_CONNS=$(ss -tn | grep ":5432" | wc -l 2>/dev/null || echo "0")
    PGBOUNCER_CONNS=$(ss -tn | grep ":6432" | wc -l 2>/dev/null || echo "0")
    echo "   📊 Current connections: Direct=$DIRECT_CONNS, PgBouncer=$PGBOUNCER_CONNS"
    
    # 6. Final stabilization wait
    echo "   ⏳ Final stabilization wait (20 seconds)..."
    for i in {20..1}; do
        echo -ne "   ⏰ $i seconds remaining...\r"
        sleep 1
    done
    echo -ne "   ✅ Cleanup completed!                    \n"
    echo ""
}

echo "======================================"
echo "PgBouncer Performance Comparison Test"
echo "======================================"
echo "Started at: $(date)"
echo "Results will be saved to: $RESULTS_DIR"
echo ""
echo "Configuration:"
echo "  Database: $DB_HOST:$DB_PORT/$DB_NAME"
echo "  PgBouncer: $PGBOUNCER_HOST:$PGBOUNCER_PORT"
echo "  User: $DB_USERNAME"
echo ""
echo "🧹 Test Isolation Features:"
echo "  ✅ FULL cleanup between direct and PgBouncer tests within each test case"
echo "  ✅ FULL cleanup between different test cases"
echo "  ✅ Database statistics reset"
echo "  ✅ PgBouncer pool reset (PAUSE/RESUME)"
echo "  ✅ TCP connection settling waits"
echo "  ✅ OS cache clearing attempts"
echo "  ✅ Extended stabilization periods"
echo "  → Maximum test isolation for most accurate results!"
echo ""

# Verify connections before starting tests
echo "Verifying connections..."

if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "❌ Direct database connection failed!"
    echo "Check your database configuration and network connectivity."
    exit 1
fi
echo "✅ Direct database connection successful"

if ! psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "❌ PgBouncer connection failed!"
    echo "Check that PgBouncer is running and properly configured."
    exit 1
fi
echo "✅ PgBouncer connection successful"

echo ""

# Test 1: Connection Overhead Test
echo "======================================"
echo "Test 1: Connection Overhead Test"
echo "======================================"
echo "Purpose: Measure the overhead of establishing new connections"
echo "Setup: 20 clients, 100 transactions each, new connection per transaction"
echo "This is the worst-case scenario that shows PgBouncer's biggest advantage"
echo ""

echo "Running direct connection test..."
echo "⏳ This may take a while due to connection overhead..."
pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies --progress=10 \
    > "$RESULTS_DIR/direct_overhead_$TIMESTAMP.log" 2>&1

echo "✅ Direct connection test completed"

# Full cleanup before PgBouncer test within same test case
cleanup_between_tests "Direct test in Test 1 (Connection Overhead)"

echo "Running PgBouncer connection test..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies --progress=10 \
    > "$RESULTS_DIR/pgbouncer_overhead_$TIMESTAMP.log" 2>&1

echo "✅ Connection overhead test completed"

# Cleanup between tests to ensure fair comparison
cleanup_between_tests "Test 1 (Connection Overhead)"

# Test 2: High Concurrency Test
echo "======================================"
echo "Test 2: High Concurrency Test"
echo "======================================"
echo "Purpose: Test performance with many concurrent persistent connections"
echo "Setup: 80 clients, persistent connections, 25 transactions per client"
echo "Note: This approaches PostgreSQL's default max_connections=100 limit"
echo ""

echo "Running direct connection test..."
pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 80 -j 40 -t 25 -n \
    --report-latencies --progress=5 \
    > "$RESULTS_DIR/direct_concurrent_$TIMESTAMP.log" 2>&1 || echo "⚠️  Direct concurrent test failed (expected due to connection limits)"

echo "✅ Direct concurrent test completed"

# Full cleanup before PgBouncer test within same test case
cleanup_between_tests "Direct test in Test 2 (High Concurrency)"

echo "Running PgBouncer connection test..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 80 -j 40 -t 25 -n \
    --report-latencies --progress=5 \
    > "$RESULTS_DIR/pgbouncer_concurrent_$TIMESTAMP.log" 2>&1 || echo "⚠️  PgBouncer concurrent test failed"

echo "✅ High concurrency test completed"

# Cleanup between tests to ensure fair comparison
cleanup_between_tests "Test 2 (High Concurrency)"

# Test 3: Extreme Connection Test
echo "======================================"
echo "Test 3: Extreme Connection Test"
echo "======================================"
echo "Purpose: Test connection limits (direct should fail, PgBouncer should succeed)"
echo "Setup: 1000 clients - this exceeds PostgreSQL's default max_connections=100"
echo ""

echo "Running direct connection test (expected to fail)..."
echo "⚠️  This test is expected to fail due to connection limits"
timeout 300 pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 1000 -j 100 -t 5 -n \
    --report-latencies \
    > "$RESULTS_DIR/direct_extreme_$TIMESTAMP.log" 2>&1 || echo "❌ Direct connection failed as expected (connection limit exceeded)"

echo "✅ Direct extreme test completed"

# Full cleanup before PgBouncer test within same test case
cleanup_between_tests "Direct test in Test 3 (Extreme Connection)"

echo "Running PgBouncer connection test..."
echo "⏳ This may take a while with 1000 clients..."
timeout 600 pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 1000 -j 100 -t 5 -n \
    --report-latencies --progress=2 \
    > "$RESULTS_DIR/pgbouncer_extreme_$TIMESTAMP.log" 2>&1 || echo "⚠️  PgBouncer extreme test failed or timed out"

echo "✅ Extreme connection test completed"
echo ""

# Generate summary report
echo "======================================"
echo "Generating Performance Analysis"
echo "======================================"

if command -v python3 > /dev/null && [ -f "analyze_results.py" ]; then
    python3 analyze_results.py "$RESULTS_DIR" "$TIMESTAMP"
elif [ -f "/home/ubuntu/analyze_results.py" ]; then
    python3 /home/ubuntu/analyze_results.py "$RESULTS_DIR" "$TIMESTAMP"
else
    echo "Analysis script not found, generating basic summary..."
    
    # Create a basic summary
    cat > "$RESULTS_DIR/summary_$TIMESTAMP.txt" << EOF
PgBouncer Performance Test Results
==================================
Generated: $(date)

Test Results Location: $RESULTS_DIR

Files generated:
- direct_overhead_$TIMESTAMP.log     - Direct connection overhead test
- pgbouncer_overhead_$TIMESTAMP.log  - PgBouncer overhead test
- direct_concurrent_$TIMESTAMP.log   - Direct high concurrency test
- pgbouncer_concurrent_$TIMESTAMP.log - PgBouncer high concurrency test
- direct_extreme_$TIMESTAMP.log      - Direct extreme load test
- pgbouncer_extreme_$TIMESTAMP.log   - PgBouncer extreme load test

To analyze results manually:
1. Look for "tps = " lines for throughput
2. Look for "latency average = " lines for latency
3. Look for error messages in direct_extreme_*.log

Expected Results:
- PgBouncer should show 2x+ throughput in overhead test
- PgBouncer should show 50%+ lower latency in overhead test
- Direct extreme test should fail with connection errors
- PgBouncer extreme test should succeed

Key Benefits Demonstrated:
1. Connection pooling eliminates connection establishment overhead
2. PgBouncer enables high concurrency beyond database limits
3. Better resource utilization and performance
EOF
fi

echo ""
echo "======================================"
echo "🎉 Performance Test Completed!"
echo "======================================"
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Quick commands to view results:"
echo "  cat $RESULTS_DIR/summary_$TIMESTAMP.txt"
echo "  grep 'tps =' $RESULTS_DIR/*_$TIMESTAMP.log"
echo "  grep 'latency average' $RESULTS_DIR/*_$TIMESTAMP.log"
echo ""
echo "Individual test logs:"
for log in "$RESULTS_DIR"/*_"$TIMESTAMP".log; do
    if [ -f "$log" ]; then
        echo "  $(basename "$log")"
    fi
done
echo ""
echo "💡 Don't forget to run 'terraform destroy' when you're done testing!"
echo "======================================" 