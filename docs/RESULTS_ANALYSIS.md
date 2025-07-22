# PgBouncer Performance Test - Results Analysis Guide

This guide helps you understand and interpret the performance test results from the PgBouncer vs. direct connection comparison.

## Table of Contents
- [Test Overview](#test-overview)
- [Understanding the Metrics](#understanding-the-metrics)
- [Test Scenarios Explained](#test-scenarios-explained)
- [Expected Results](#expected-results)
- [Interpreting Your Results](#interpreting-your-results)
- [Real-World Implications](#real-world-implications)
- [Advanced Analysis](#advanced-analysis)
- [Common Patterns](#common-patterns)

## Test Overview

The performance test suite runs three key scenarios to demonstrate different aspects of PgBouncer's benefits:

1. **Connection Overhead Test**: Shows the cost of establishing new database connections
2. **High Concurrency Test**: Demonstrates handling many simultaneous connections
3. **Extreme Load Test**: Tests connection limits and failure scenarios

## Understanding the Metrics

### Primary Metrics

#### Transactions Per Second (TPS)
- **What it measures**: Number of database transactions completed per second
- **Higher is better**: More TPS = better throughput
- **Typical range**: 10-1000+ TPS depending on workload and hardware

#### Latency (ms)
- **What it measures**: Average time from query start to completion
- **Lower is better**: Less latency = faster response times
- **Components**: Network time + connection time + query execution time

#### Connection Time (ms)
- **What it measures**: Time to establish a new database connection
- **Only shown with `-C` flag**: Forces new connection per transaction
- **PgBouncer advantage**: Reuses existing connections, nearly eliminating this overhead

### Secondary Metrics

#### Latency Standard Deviation
- **What it measures**: Consistency of response times
- **Lower is better**: Less variation = more predictable performance

#### Failed Transactions
- **What it measures**: Transactions that couldn't complete
- **Common causes**: Connection limits, timeouts, database errors

## Test Scenarios Explained

### Scenario 1: Connection Overhead Test
```bash
pgbench -c 20 -j 20 -t 100 -C -n
```

**Parameters**:
- `-c 20`: 20 concurrent clients
- `-j 20`: 20 worker threads
- `-t 100`: 100 transactions per client (2000 total)
- `-C`: New connection for each transaction (worst case)
- `-n`: Skip vacuum (focus on connection overhead)

**Purpose**: This test demonstrates the "worst case" scenario where every transaction requires a new database connection. In real applications, this might occur with:
- Serverless functions
- Short-lived processes
- Poor connection management

**Expected outcome**:
- Direct connections: High latency due to connection establishment
- PgBouncer: Much faster due to connection reuse

### Scenario 2: High Concurrency Test
```bash
pgbench -c 100 -j 50 -t 10 -n
```

**Parameters**:
- `-c 100`: 100 concurrent clients
- `-j 50`: 50 worker threads
- `-t 10`: 10 transactions per client (1000 total)
- No `-C`: Persistent connections when possible

**Purpose**: Tests behavior with many concurrent connections that stay open. This simulates:
- Web applications with connection pooling
- Multiple application servers
- High-traffic scenarios

**Expected outcome**:
- Direct connections: May approach connection limits
- PgBouncer: Handles high client count with efficient server connection usage

### Scenario 3: Extreme Load Test
```bash
pgbench -c 1000 -j 100 -t 5 -n
```

**Parameters**:
- `-c 1000`: 1000 concurrent clients
- `-j 100`: 100 worker threads  
- `-t 5`: 5 transactions per client (5000 total)

**Purpose**: Stress test that exceeds PostgreSQL's default connection limit (100). This demonstrates:
- Connection limit problems with direct connections
- PgBouncer's ability to queue and multiplex connections

**Expected outcome**:
- Direct connections: **Should fail** with "too many clients" errors
- PgBouncer: Should succeed by queuing excess connections

## Expected Results

### Baseline Performance (Typical Results)

#### Connection Overhead Test (20 clients, new connection each)
| Metric | Direct to DB | Via PgBouncer | Improvement |
|--------|--------------|---------------|-------------|
| **TPS** | ~58 | ~112 | **~2x faster** |
| **Latency** | ~340ms | ~178ms | **50% reduction** |
| **Connection Time** | ~300ms | ~50ms | **6x faster** |

#### High Concurrency Test (100 persistent connections)
| Metric | Direct to DB | Via PgBouncer | Improvement |
|--------|--------------|---------------|-------------|
| **TPS** | ~180 | ~220 | **~20% faster** |
| **Latency** | ~55ms | ~45ms | **18% reduction** |

#### Extreme Load Test (1000 connections)
| Metric | Direct to DB | Via PgBouncer | Result |
|--------|--------------|---------------|---------|
| **Status** | ❌ FAILED | ✅ SUCCESS | **Reliability** |
| **Error** | "too many clients" | None | **Fault tolerance** |
| **TPS** | 0 | ~900 | **Infinite improvement** |

### Factors Affecting Results

#### Instance Size Impact
- **t3.micro**: Basic results, some variability
- **t3.medium**: More consistent, higher absolute numbers
- **t3.large**: Best consistency, highest performance

#### Network Latency
- **Same AZ**: Lowest latency (~1-2ms base)
- **Different AZ**: Medium latency (~5-10ms base)
- **Different region**: Higher latency (50-200ms base)

#### Database Load
- **Empty database**: Best performance
- **With existing data**: Slightly lower performance
- **Under concurrent load**: Variable performance

## Interpreting Your Results

### Good Results Indicators

✅ **Connection Overhead Test**:
- PgBouncer shows 2x+ improvement in TPS
- Latency reduction of 40%+
- Connection time significantly lower with PgBouncer

✅ **High Concurrency Test**:
- Both tests complete successfully
- PgBouncer shows modest improvements
- No connection errors

✅ **Extreme Load Test**:
- Direct connection fails with "too many clients"
- PgBouncer completes successfully
- PgBouncer achieves reasonable TPS (500+)

### Warning Signs

⚠️ **Inconsistent Results**:
- Large variations between test runs
- **Possible causes**: Noisy neighbors, instance throttling, network issues
- **Solution**: Run tests multiple times, use larger instances

⚠️ **No Improvement Shown**:
- PgBouncer not significantly better than direct
- **Possible causes**: Network bottleneck, database bottleneck, configuration issues
- **Investigation**: Check pool status, monitor resources

⚠️ **Both Tests Failing**:
- Neither direct nor PgBouncer completing
- **Possible causes**: Database down, network issues, incorrect configuration
- **Investigation**: Check connectivity, logs, AWS console

### Red Flags

🚨 **PgBouncer Worse Than Direct**:
- PgBouncer showing lower performance
- **Possible causes**: Misconfiguration, resource constraints, pool exhaustion
- **Investigation**: Check PgBouncer logs, pool status, system resources

🚨 **Extreme Load Test Succeeds for Direct**:
- 1000 connections work without PgBouncer
- **Possible causes**: max_connections was increased, test not actually using 1000 connections
- **Investigation**: Verify PostgreSQL configuration, check actual connection count

## Real-World Implications

### Connection Overhead Reduction

**Before PgBouncer**:
```
Client Request → New DB Connection (300ms) → Query (50ms) → Close Connection
Total: 350ms per request
```

**With PgBouncer**:
```
Client Request → PgBouncer (2ms) → Existing DB Connection → Query (50ms)
Total: 52ms per request
```

**Real-world impact**:
- Web applications feel much more responsive
- API endpoints respond faster
- Better user experience under load

### Scalability Improvements

**Connection Limits**:
- **Without PgBouncer**: Limited to database max_connections (typically 100-200)
- **With PgBouncer**: Can handle thousands of client connections

**Resource Efficiency**:
- **Database memory**: Each connection uses ~8MB in PostgreSQL
- **Context switching**: Fewer connections = less CPU overhead
- **Lock contention**: Reduced with fewer active connections

### Cost Implications

**Infrastructure Costs**:
- **Database scaling**: Can delay need for larger database instances
- **Application scaling**: Better resource utilization
- **Monitoring**: Fewer connection-related issues to debug

**Operational Benefits**:
- **Reliability**: Graceful handling of connection spikes
- **Monitoring**: Centralized connection metrics
- **Maintenance**: Easier to manage connection-related issues

## Advanced Analysis

### Custom Metrics Collection

#### Monitoring PgBouncer
```sql
-- Pool utilization
SELECT database, cl_active, cl_waiting, sv_active, sv_idle 
FROM pgbouncer.pools;

-- Connection statistics
SELECT database, total_requests, total_received, total_sent, total_query_time
FROM pgbouncer.stats;
```

#### PostgreSQL Monitoring
```sql
-- Active connections
SELECT count(*), state FROM pg_stat_activity GROUP BY state;

-- Connection usage by database
SELECT datname, numbackends FROM pg_stat_database;

-- Lock waits
SELECT count(*) FROM pg_locks WHERE NOT granted;
```

### Performance Tuning

#### PgBouncer Optimization
```ini
# For high-throughput workloads
default_pool_size = 200
reserve_pool_size = 50
max_client_conn = 2000

# For low-latency workloads  
pool_mode = session
server_idle_timeout = 300
```

#### PostgreSQL Optimization
```sql
-- Increase connection limit (with caution)
ALTER SYSTEM SET max_connections = 200;

-- Optimize for connections
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET max_prepared_transactions = 100;
```

### Benchmarking Variations

#### Different Workload Patterns
```bash
# Read-heavy workload
pgbench -S -c 50 -j 25 -t 100

# Write-heavy workload
pgbench -N -c 20 -j 10 -t 50

# Mixed workload (default)
pgbench -c 30 -j 15 -t 75
```

#### Connection Pattern Testing
```bash
# Burst connections
for i in {1..10}; do pgbench -c 100 -j 50 -t 5 & done; wait

# Sustained load
pgbench -c 50 -j 25 -T 300  # 5 minutes
```

## Common Patterns

### Expected Improvement Ranges

| Scenario | TPS Improvement | Latency Improvement |
|----------|----------------|-------------------|
| **Connection overhead** | 150-300% | 40-70% |
| **High concurrency** | 10-50% | 10-30% |
| **Steady state** | 5-20% | 5-15% |

### Scaling Characteristics

**Linear improvements** (more clients = more benefit):
- Connection establishment overhead
- Memory usage efficiency
- Connection limit handling

**Diminishing returns** (plateau at higher loads):
- Query execution performance
- Database CPU utilization
- Network throughput

### Troubleshooting Performance

#### If Results Are Lower Than Expected

1. **Check system resources**:
   ```bash
   htop  # CPU and memory usage
   iostat 1  # Disk I/O
   iftop  # Network usage
   ```

2. **Verify PgBouncer configuration**:
   ```bash
   sudo cat /etc/pgbouncer/pgbouncer.ini
   psql -p 6432 -U postgres -d pgbouncer -c "SHOW CONFIG;"
   ```

3. **Monitor during tests**:
   ```bash
   # Terminal 1: Run test
   ./run_performance_test.sh
   
   # Terminal 2: Monitor PgBouncer
   watch 'psql -p 6432 -U postgres -d pgbouncer -c "SHOW POOLS;"'
   
   # Terminal 3: Monitor database
   watch 'psql -h <db-host> -U postgres -d testdb -c "SELECT count(*) FROM pg_stat_activity;"'
   ```

## Conclusion

The performance tests demonstrate that PgBouncer provides significant benefits:

1. **Dramatic improvement** in connection-heavy workloads (2x+ throughput)
2. **Modest but meaningful** improvements in normal operation (10-20%)
3. **Critical reliability** benefits when approaching connection limits
4. **Resource efficiency** allowing better utilization of database resources

These improvements translate to real-world benefits including faster application response times, better scalability, and improved reliability under load.

The specific numbers you see will vary based on your infrastructure, but the relative improvements should be consistent with the patterns described in this guide. 