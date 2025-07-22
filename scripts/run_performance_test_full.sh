#!/bin/bash

# PgBouncer Performance Comparison Test
# This script runs comprehensive performance tests comparing direct vs pooled connections

source /home/ubuntu/.env

RESULTS_DIR="/home/ubuntu/test_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

echo "======================================"
echo "PgBouncer Performance Comparison Test"
echo "======================================"
echo "Started at: $(date)"
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Test 1: Connection Overhead Test (20 clients, 100 transactions each, new connection per transaction)
echo "Test 1: Connection Overhead Test"
echo "- 20 clients, 100 transactions each"
echo "- New connection per transaction (worst case)"
echo ""

echo "Running direct connection test..."
pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies --progress=10 \
    > "$RESULTS_DIR/direct_overhead_$TIMESTAMP.log" 2>&1

echo "Running PgBouncer connection test..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies --progress=10 \
    > "$RESULTS_DIR/pgbouncer_overhead_$TIMESTAMP.log" 2>&1

# Test 2: High Concurrency Test (100 clients, persistent connections)
echo "Test 2: High Concurrency Test"
echo "- 100 clients, persistent connections"
echo "- 10 transactions per client"
echo ""

echo "Running direct connection test..."
pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 100 -j 50 -t 10 -n \
    --report-latencies --progress=5 \
    > "$RESULTS_DIR/direct_concurrent_$TIMESTAMP.log" 2>&1

echo "Running PgBouncer connection test..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 100 -j 50 -t 10 -n \
    --report-latencies --progress=5 \
    > "$RESULTS_DIR/pgbouncer_concurrent_$TIMESTAMP.log" 2>&1

# Test 3: Extreme Connection Test (1000 clients - this should fail for direct)
echo "Test 3: Extreme Connection Test"
echo "- 1000 clients (direct connection should fail)"
echo ""

echo "Running direct connection test (expected to fail)..."
timeout 300 pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 1000 -j 100 -t 5 -n \
    --report-latencies \
    > "$RESULTS_DIR/direct_extreme_$TIMESTAMP.log" 2>&1 || echo "Direct connection failed as expected"

echo "Running PgBouncer connection test..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 1000 -j 100 -t 5 -n \
    --report-latencies --progress=2 \
    > "$RESULTS_DIR/pgbouncer_extreme_$TIMESTAMP.log" 2>&1

# Generate summary report
echo "Generating performance summary..."
python3 /home/ubuntu/analyze_results.py "$RESULTS_DIR" "$TIMESTAMP"

echo ""
echo "======================================"
echo "Performance test completed!"
echo "Results saved to: $RESULTS_DIR"
echo "View summary: cat $RESULTS_DIR/summary_$TIMESTAMP.txt"
echo "======================================" 