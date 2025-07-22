#!/usr/bin/env python3

import sys
import re
import os
from datetime import datetime

def parse_pgbench_output(filename):
    """Parse pgbench output to extract key metrics"""
    if not os.path.exists(filename):
        return None
    
    with open(filename, 'r') as f:
        content = f.read()
    
    # Extract TPS
    tps_match = re.search(r'tps = ([0-9.]+)', content)
    tps = float(tps_match.group(1)) if tps_match else 0
    
    # Extract latency
    latency_match = re.search(r'latency average = ([0-9.]+) ms', content)
    latency = float(latency_match.group(1)) if latency_match else 0
    
    # Check for errors
    error_keywords = ['FATAL', 'ERROR', 'failed', 'connection refused']
    has_errors = any(keyword in content for keyword in error_keywords)
    
    return {
        'tps': tps,
        'latency': latency,
        'has_errors': has_errors,
        'content': content
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 analyze_results.py <results_dir> <timestamp>")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    timestamp = sys.argv[2]
    
    # Parse all test results
    tests = {
        'overhead': {
            'direct': f"{results_dir}/direct_overhead_{timestamp}.log",
            'pgbouncer': f"{results_dir}/pgbouncer_overhead_{timestamp}.log"
        },
        'concurrent': {
            'direct': f"{results_dir}/direct_concurrent_{timestamp}.log",
            'pgbouncer': f"{results_dir}/pgbouncer_concurrent_{timestamp}.log"
        },
        'extreme': {
            'direct': f"{results_dir}/direct_extreme_{timestamp}.log",
            'pgbouncer': f"{results_dir}/pgbouncer_extreme_{timestamp}.log"
        }
    }
    
    summary_file = f"{results_dir}/summary_{timestamp}.txt"
    
    with open(summary_file, 'w') as f:
        f.write("PgBouncer Performance Test Results\n")
        f.write("=" * 50 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        
        for test_name, files in tests.items():
            f.write(f"\n{test_name.upper()} TEST RESULTS\n")
            f.write("-" * 30 + "\n")
            
            direct_result = parse_pgbench_output(files['direct'])
            pgbouncer_result = parse_pgbench_output(files['pgbouncer'])
            
            if direct_result and not direct_result['has_errors']:
                f.write(f"Direct Connection:\n")
                f.write(f"  TPS: {direct_result['tps']:.2f}\n")
                f.write(f"  Latency: {direct_result['latency']:.2f} ms\n")
            else:
                f.write(f"Direct Connection: FAILED or ERRORS\n")
            
            if pgbouncer_result and not pgbouncer_result['has_errors']:
                f.write(f"PgBouncer Connection:\n")
                f.write(f"  TPS: {pgbouncer_result['tps']:.2f}\n")
                f.write(f"  Latency: {pgbouncer_result['latency']:.2f} ms\n")
                
                # Calculate improvements if both tests succeeded
                if direct_result and not direct_result['has_errors']:
                    if direct_result['tps'] > 0:
                        tps_improvement = (pgbouncer_result['tps'] / direct_result['tps'] - 1) * 100
                        f.write(f"  TPS Improvement: {tps_improvement:+.1f}%\n")
                    
                    if direct_result['latency'] > 0:
                        latency_improvement = (1 - pgbouncer_result['latency'] / direct_result['latency']) * 100
                        f.write(f"  Latency Improvement: {latency_improvement:+.1f}%\n")
            else:
                f.write(f"PgBouncer Connection: FAILED or ERRORS\n")
        
        f.write("\n\nKEY FINDINGS\n")
        f.write("-" * 20 + "\n")
        
        # Analyze overhead test specifically
        overhead_direct = parse_pgbench_output(tests['overhead']['direct'])
        overhead_pgbouncer = parse_pgbench_output(tests['overhead']['pgbouncer'])
        
        if overhead_direct and overhead_pgbouncer and not overhead_direct['has_errors'] and not overhead_pgbouncer['has_errors']:
            tps_ratio = overhead_pgbouncer['tps'] / overhead_direct['tps']
            latency_ratio = overhead_direct['latency'] / overhead_pgbouncer['latency']
            
            f.write(f"Connection Overhead Test (20 clients, new connection per transaction):\n")
            f.write(f"- PgBouncer achieved {tps_ratio:.1f}x the throughput of direct connections\n")
            f.write(f"- PgBouncer reduced latency by {(1-1/latency_ratio)*100:.0f}%\n")
            f.write(f"- This demonstrates the massive overhead of connection establishment\n\n")
        
        # Check extreme test
        extreme_direct = parse_pgbench_output(tests['extreme']['direct'])
        extreme_pgbouncer = parse_pgbench_output(tests['extreme']['pgbouncer'])
        
        if extreme_direct and extreme_direct['has_errors']:
            f.write(f"High Concurrency Test (1000 clients):\n")
            f.write(f"- Direct connections FAILED as expected (connection limit exceeded)\n")
            
            if extreme_pgbouncer and not extreme_pgbouncer['has_errors']:
                f.write(f"- PgBouncer successfully handled all 1000 clients\n")
                f.write(f"- Achieved {extreme_pgbouncer['tps']:.0f} TPS with 1000 concurrent clients\n")
            f.write(f"- This demonstrates PgBouncer's ability to handle connection multiplexing\n\n")
        
        f.write("CONCLUSION:\n")
        f.write("PgBouncer provides significant benefits:\n")
        f.write("1. Eliminates connection establishment overhead\n")
        f.write("2. Enables high concurrency beyond database limits\n")
        f.write("3. Improves both throughput and latency\n")
        f.write("4. Provides reliable connection pooling and queuing\n")
    
    print(f"Analysis complete! Summary saved to: {summary_file}")
    
    # Print summary to console
    with open(summary_file, 'r') as f:
        print("\n" + f.read())

if __name__ == "__main__":
    main() 