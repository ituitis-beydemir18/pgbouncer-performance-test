#!/bin/bash

# Test Client Setup Script
# This script installs PostgreSQL client tools and performance test scripts

set -e

# Log all output
exec > >(tee /var/log/client-setup.log)
exec 2>&1

echo "Starting test client setup at $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install PostgreSQL client, pgbench, and other tools
apt-get install -y postgresql-client postgresql-contrib python3 python3-pip htop sysstat

# Install Python packages for analysis
pip3 install psycopg2-binary matplotlib pandas

# Database and PgBouncer connection details from Terraform
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"
PGBOUNCER_HOST="${pgbouncer_host}"
PGBOUNCER_PORT="${pgbouncer_port}"

echo "Configuring test client for:"
echo "  Database: $DB_HOST:$DB_PORT"
echo "  PgBouncer: $PGBOUNCER_HOST:$PGBOUNCER_PORT"

# Set environment variables
cat > /home/ubuntu/.env << EOF
export DB_HOST="$DB_HOST"
export DB_PORT="$DB_PORT"
export DB_NAME="$DB_NAME"
export DB_USERNAME="$DB_USERNAME"
export DB_PASSWORD="$DB_PASSWORD"
export PGBOUNCER_HOST="$PGBOUNCER_HOST"
export PGBOUNCER_PORT="$PGBOUNCER_PORT"
export PGPASSWORD="$DB_PASSWORD"
EOF

# Source environment in bash profile
echo "source /home/ubuntu/.env" >> /home/ubuntu/.bashrc

# Wait for PgBouncer to be ready
echo "Waiting for PgBouncer to be ready..."
for i in {1..60}; do
    if pg_isready -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT"; then
        echo "PgBouncer is ready!"
        break
    fi
    echo "Waiting for PgBouncer... attempt $i/60"
    sleep 5
done

# Test connections
echo "Testing database connections..."
export PGPASSWORD="$DB_PASSWORD"

# Test direct connection
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Direct database connection successful"
else
    echo "✗ Direct database connection failed"
fi

# Test PgBouncer connection
if psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ PgBouncer connection successful"
else
    echo "✗ PgBouncer connection failed"
fi

# Create comprehensive performance test script
cat > /home/ubuntu/run_performance_test.sh << 'EOSCRIPT'
#!/bin/bash

# PgBouncer Performance Comparison Test
# This script runs comprehensive performance tests comparing direct vs pooled connections

set -e

# Source environment variables
if [ -f "/home/ubuntu/.env" ]; then
    source /home/ubuntu/.env
fi

# Configuration
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
echo "Purpose: Measure overhead of establishing new connections (worst case scenario)"
echo "Setup: 20 clients, 100 transactions each, NEW connection per transaction"
echo ""

echo "Running direct connection test (with connection overhead)..."
pgbench -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies \
    > "$RESULTS_DIR/direct_overhead_$TIMESTAMP.log" 2>&1

echo "Running PgBouncer connection test (with connection reuse)..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 20 -j 20 -t 100 -C -n \
    --report-latencies \
    > "$RESULTS_DIR/pgbouncer_overhead_$TIMESTAMP.log" 2>&1

echo "✅ Connection overhead test completed"
echo ""

# Test 2: High Concurrency Test
echo "======================================"
echo "Test 2: High Concurrency Test"
echo "======================================"
echo "Purpose: Test performance with many concurrent persistent connections"
echo "Setup: 100 clients, persistent connections, 10 transactions per client"
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

echo "✅ High concurrency test completed"
echo ""

# Test 3: Extreme Connection Load Test
echo "======================================"
echo "Test 3: Extreme Connection Load Test"
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

echo "Running PgBouncer connection test..."
echo "⏳ This may take a while with 1000 clients..."
pgbench -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" \
    -c 1000 -j 100 -t 5 -n \
    --report-latencies --progress=2 \
    > "$RESULTS_DIR/pgbouncer_extreme_$TIMESTAMP.log" 2>&1

echo "✅ Extreme connection test completed"
echo ""

# Generate summary report
echo "======================================"
echo "Generating Performance Analysis"
echo "======================================"

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

Key Metrics to Compare:
=======================

1. Connection Overhead Test:
   - Check 'latency average' and 'tps' values
   - PgBouncer should show significantly better performance

2. High Concurrency Test:
   - Compare 'tps' (transactions per second)
   - Look for any connection errors in direct test

3. Extreme Load Test:
   - Direct test should fail with connection errors
   - PgBouncer test should complete successfully

Quick Analysis Commands:
========================
grep "tps =" $RESULTS_DIR/*_$TIMESTAMP.log
grep "latency average" $RESULTS_DIR/*_$TIMESTAMP.log
grep -i error $RESULTS_DIR/*_$TIMESTAMP.log

EOF

echo "📊 Performance test completed successfully!"
echo ""
echo "Results summary saved to: $RESULTS_DIR/summary_$TIMESTAMP.txt"
echo ""
echo "Quick results:"
echo "=============="
echo ""

# Show quick results
echo "Connection Overhead Test Results:"
echo "---------------------------------"
if [ -f "$RESULTS_DIR/direct_overhead_$TIMESTAMP.log" ]; then
    echo "Direct DB:"
    grep "tps\|latency average" "$RESULTS_DIR/direct_overhead_$TIMESTAMP.log" | head -2
fi
if [ -f "$RESULTS_DIR/pgbouncer_overhead_$TIMESTAMP.log" ]; then
    echo "PgBouncer:"
    grep "tps\|latency average" "$RESULTS_DIR/pgbouncer_overhead_$TIMESTAMP.log" | head -2
fi

echo ""
echo "High Concurrency Test Results:"
echo "-------------------------------"
if [ -f "$RESULTS_DIR/direct_concurrent_$TIMESTAMP.log" ]; then
    echo "Direct DB:"
    grep "tps\|latency average" "$RESULTS_DIR/direct_concurrent_$TIMESTAMP.log" | head -2
fi
if [ -f "$RESULTS_DIR/pgbouncer_concurrent_$TIMESTAMP.log" ]; then
    echo "PgBouncer:"
    grep "tps\|latency average" "$RESULTS_DIR/pgbouncer_concurrent_$TIMESTAMP.log" | head -2
fi

echo ""
echo "📁 View detailed logs: ls -la $RESULTS_DIR/"
echo "📊 View summary: cat $RESULTS_DIR/summary_$TIMESTAMP.txt"
echo ""
echo "🎉 All tests completed! Check the results above."
EOSCRIPT

# Create individual test scripts
cat > /home/ubuntu/test_direct_connection.sh << 'EOSCRIPT'
#!/bin/bash
source /home/ubuntu/.env
echo "Testing direct PostgreSQL connection..."
export PGPASSWORD="$DB_PASSWORD"
time psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();"
EOSCRIPT

cat > /home/ubuntu/test_pgbouncer.sh << 'EOSCRIPT'
#!/bin/bash
source /home/ubuntu/.env
echo "Testing PgBouncer connection..."
export PGPASSWORD="$DB_PASSWORD"
time psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();"
EOSCRIPT

# Create analysis script
cat > /home/ubuntu/analyze_results.py << 'EOSCRIPT'
#!/usr/bin/env python3
import os
import sys
import re
from datetime import datetime

def analyze_pgbench_log(file_path):
    """Parse pgbench log file and extract key metrics"""
    if not os.path.exists(file_path):
        return None
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    metrics = {}
    
    # Extract TPS
    tps_match = re.search(r'tps = ([\d.]+)', content)
    if tps_match:
        metrics['tps'] = float(tps_match.group(1))
    
    # Extract average latency
    lat_match = re.search(r'latency average = ([\d.]+) ms', content)
    if lat_match:
        metrics['latency_avg'] = float(lat_match.group(1))
    
    # Extract connection time
    conn_match = re.search(r'connection time = ([\d.]+) ms', content)
    if conn_match:
        metrics['connection_time'] = float(conn_match.group(1))
    
    # Check for errors
    if 'FATAL' in content or 'ERROR' in content or 'failed' in content.lower():
        metrics['has_errors'] = True
    else:
        metrics['has_errors'] = False
    
    return metrics

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 analyze_results.py <results_dir> <timestamp>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    timestamp = sys.argv[2]
    
    # Define test types and their files
    tests = {
        'Connection Overhead': {
            'direct': f'direct_overhead_{timestamp}.log',
            'pgbouncer': f'pgbouncer_overhead_{timestamp}.log'
        },
        'High Concurrency': {
            'direct': f'direct_concurrent_{timestamp}.log',
            'pgbouncer': f'pgbouncer_concurrent_{timestamp}.log'
        },
        'Extreme Load': {
            'direct': f'direct_extreme_{timestamp}.log',
            'pgbouncer': f'pgbouncer_extreme_{timestamp}.log'
        }
    }
    
    print("=" * 50)
    print("PgBouncer Performance Analysis")
    print("=" * 50)
    print(f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    for test_name, files in tests.items():
        print(f"{test_name} Test Results:")
        print("-" * (len(test_name) + 14))
        
        direct_file = os.path.join(results_dir, files['direct'])
        pgbouncer_file = os.path.join(results_dir, files['pgbouncer'])
        
        direct_metrics = analyze_pgbench_log(direct_file)
        pgbouncer_metrics = analyze_pgbench_log(pgbouncer_file)
        
        if direct_metrics and pgbouncer_metrics:
            print(f"{'Metric':<20} {'Direct DB':<15} {'PgBouncer':<15} {'Improvement':<15}")
            print("-" * 65)
            
            # TPS comparison
            if 'tps' in direct_metrics and 'tps' in pgbouncer_metrics:
                improvement = (pgbouncer_metrics['tps'] / direct_metrics['tps'] - 1) * 100
                print(f"{'TPS':<20} {direct_metrics['tps']:<15.1f} {pgbouncer_metrics['tps']:<15.1f} {improvement:>+13.1f}%")
            
            # Latency comparison
            if 'latency_avg' in direct_metrics and 'latency_avg' in pgbouncer_metrics:
                improvement = (1 - pgbouncer_metrics['latency_avg'] / direct_metrics['latency_avg']) * 100
                print(f"{'Latency (ms)':<20} {direct_metrics['latency_avg']:<15.1f} {pgbouncer_metrics['latency_avg']:<15.1f} {improvement:>+13.1f}%")
            
            # Connection time comparison
            if 'connection_time' in direct_metrics and 'connection_time' in pgbouncer_metrics:
                improvement = (1 - pgbouncer_metrics['connection_time'] / direct_metrics['connection_time']) * 100
                print(f"{'Connection (ms)':<20} {direct_metrics['connection_time']:<15.1f} {pgbouncer_metrics['connection_time']:<15.1f} {improvement:>+13.1f}%")
            
            # Error status
            direct_status = "❌ FAILED" if direct_metrics['has_errors'] else "✅ SUCCESS"
            pgbouncer_status = "❌ FAILED" if pgbouncer_metrics['has_errors'] else "✅ SUCCESS"
            print(f"{'Status':<20} {direct_status:<15} {pgbouncer_status:<15}")
            
        else:
            print("❌ Could not analyze results - check log files")
        
        print()
    
    print("Summary:")
    print("- PgBouncer typically shows 50-200% improvement in throughput")
    print("- Latency reduction is most significant with connection overhead (-C flag)")
    print("- Extreme load tests demonstrate PgBouncer's connection multiplexing capabilities")
    print()

if __name__ == "__main__":
    main()
EOSCRIPT

chmod +x /home/ubuntu/run_performance_test.sh
chmod +x /home/ubuntu/test_direct_connection.sh
chmod +x /home/ubuntu/test_pgbouncer.sh
chmod +x /home/ubuntu/analyze_results.py

# Set ownership of all files
chown -R ubuntu:ubuntu /home/ubuntu/

echo "Test client setup completed successfully at $(date)"
echo ""
echo "Setup complete! Ready for performance testing." 