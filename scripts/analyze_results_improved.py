#!/usr/bin/env python3

import sys
import re
import os
from datetime import datetime

def parse_pgbench_output_detailed(filename):
    """Parse pgbench output to extract comprehensive metrics including reliability"""
    if not os.path.exists(filename):
        return None
    
    with open(filename, 'r') as f:
        content = f.read()
    
    # Basic performance metrics
    tps_match = re.search(r'tps = ([0-9.]+)', content)
    tps = float(tps_match.group(1)) if tps_match else 0
    
    latency_match = re.search(r'latency average = ([0-9.]+) ms', content)
    latency = float(latency_match.group(1)) if latency_match else 0
    
    # Advanced latency metrics
    latency_stddev_match = re.search(r'latency stddev = ([0-9.]+) ms', content)
    latency_stddev = float(latency_stddev_match.group(1)) if latency_stddev_match else 0
    
    # Extract transaction counts
    scaling_match = re.search(r'scaling factor: ([0-9]+)', content)
    scaling_factor = int(scaling_match.group(1)) if scaling_match else 0
    
    # Number of clients and transactions
    clients_match = re.search(r'number of clients: ([0-9]+)', content)
    clients = int(clients_match.group(1)) if clients_match else 0
    
    transactions_match = re.search(r'number of transactions per client: ([0-9]+)', content)
    transactions_per_client = int(transactions_match.group(1)) if transactions_match else 0
    
    # Total transactions attempted
    total_transactions_attempted = clients * transactions_per_client
    
    # Extract actual transactions processed
    transactions_processed_match = re.search(r'number of transactions actually processed: ([0-9]+)', content)
    transactions_processed = int(transactions_processed_match.group(1)) if transactions_processed_match else 0
    
    # Calculate success rate
    success_rate = 0
    if total_transactions_attempted > 0:
        success_rate = (transactions_processed / total_transactions_attempted) * 100
    
    # Error analysis
    error_types = {
        'connection_refused': len(re.findall(r'connection refused|could not connect', content, re.IGNORECASE)),
        'too_many_clients': len(re.findall(r'too many clients|connection limit', content, re.IGNORECASE)),
        'timeout_errors': len(re.findall(r'timeout|timed out', content, re.IGNORECASE)),
        'authentication_failed': len(re.findall(r'authentication failed|password authentication', content, re.IGNORECASE)),
        'fatal_errors': len(re.findall(r'FATAL:', content)),
        'generic_errors': len(re.findall(r'ERROR:', content))
    }
    
    # Connection rejection count
    total_connection_rejections = error_types['connection_refused'] + error_types['too_many_clients']
    
    # Overall error assessment
    has_critical_errors = any([
        error_types['connection_refused'] > 0,
        error_types['too_many_clients'] > 0,
        error_types['fatal_errors'] > 0,
        success_rate < 95  # Less than 95% success rate is considered problematic
    ])
    
    # Timeout detection
    has_timeouts = error_types['timeout_errors'] > 0 or 'timeout' in content.lower()
    
    # Performance consistency (based on standard deviation)
    performance_consistency = "Good"
    if latency_stddev > 0 and latency > 0:
        cv = (latency_stddev / latency) * 100  # Coefficient of variation
        if cv > 50:
            performance_consistency = "Poor"
        elif cv > 25:
            performance_consistency = "Fair"
    
    return {
        # Performance Metrics
        'tps': tps,
        'latency': latency,
        'latency_stddev': latency_stddev,
        'performance_consistency': performance_consistency,
        
        # Reliability Metrics
        'total_transactions_attempted': total_transactions_attempted,
        'transactions_processed': transactions_processed,
        'success_rate': success_rate,
        'error_rate': 100 - success_rate,
        
        # Connection Metrics
        'connection_rejections': total_connection_rejections,
        'timeout_rate': (error_types['timeout_errors'] / max(1, total_transactions_attempted)) * 100,
        
        # Error Classification
        'error_types': error_types,
        'has_critical_errors': has_critical_errors,
        'has_timeouts': has_timeouts,
        
        # Metadata
        'clients': clients,
        'transactions_per_client': transactions_per_client,
        'raw_content': content
    }

def generate_reliability_report(results, test_name, f):
    """Generate detailed reliability section for a test"""
    f.write(f"\n{test_name.upper()} - RELIABILITY METRICS\n")
    f.write("-" * 40 + "\n")
    
    for connection_type, result in results.items():
        if result is None:
            f.write(f"{connection_type.title()}: NO DATA\n")
            continue
            
        f.write(f"\n{connection_type.title()} Connection:\n")
        
        # Success/Error Rates
        f.write(f"  Success Rate: {result['success_rate']:.1f}%\n")
        f.write(f"  Error Rate: {result['error_rate']:.1f}%\n")
        f.write(f"  Transactions: {result['transactions_processed']}/{result['total_transactions_attempted']}\n")
        
        # Connection Issues
        if result['connection_rejections'] > 0:
            f.write(f"  Connection Rejections: {result['connection_rejections']}\n")
        
        if result['timeout_rate'] > 0:
            f.write(f"  Timeout Rate: {result['timeout_rate']:.1f}%\n")
        
        # Error Breakdown
        if any(count > 0 for count in result['error_types'].values()):
            f.write(f"  Error Breakdown:\n")
            for error_type, count in result['error_types'].items():
                if count > 0:
                    f.write(f"    {error_type.replace('_', ' ').title()}: {count}\n")
        
        # Performance Consistency
        f.write(f"  Performance Consistency: {result['performance_consistency']}\n")
        if result['latency_stddev'] > 0:
            f.write(f"  Latency Std Dev: {result['latency_stddev']:.2f}ms\n")
        
        # Overall Assessment
        if result['has_critical_errors']:
            f.write(f"  ⚠️  CRITICAL ERRORS DETECTED\n")
        elif result['success_rate'] >= 99:
            f.write(f"  ✅ EXCELLENT RELIABILITY\n")
        elif result['success_rate'] >= 95:
            f.write(f"  ✅ GOOD RELIABILITY\n")
        else:
            f.write(f"  ⚠️  POOR RELIABILITY\n")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 analyze_results_improved.py <results_dir> <timestamp>")
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
    
    summary_file = f"{results_dir}/detailed_analysis_{timestamp}.txt"
    
    with open(summary_file, 'w') as f:
        f.write("PgBouncer Performance Test - DETAILED ANALYSIS\n")
        f.write("=" * 60 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        
        f.write("This analysis includes comprehensive reliability metrics:\n")
        f.write("✅ Success/Error Rates\n")
        f.write("✅ Connection Rejection Counts\n") 
        f.write("✅ Timeout Rates\n")
        f.write("✅ Error Type Classification\n")
        f.write("✅ Performance Consistency\n\n")
        
        # Parse all results
        all_results = {}
        for test_name, files in tests.items():
            all_results[test_name] = {
                'direct': parse_pgbench_output_detailed(files['direct']),
                'pgbouncer': parse_pgbench_output_detailed(files['pgbouncer'])
            }
        
        # Generate performance summary (existing functionality)
        f.write("PERFORMANCE SUMMARY\n")
        f.write("=" * 30 + "\n")
        
        for test_name, results in all_results.items():
            f.write(f"\n{test_name.upper()} TEST\n")
            f.write("-" * 20 + "\n")
            
            for conn_type, result in results.items():
                if result and result['success_rate'] >= 95:
                    f.write(f"{conn_type.title()}: {result['tps']:.1f} TPS, {result['latency']:.1f}ms avg\n")
                else:
                    f.write(f"{conn_type.title()}: FAILED or POOR RELIABILITY\n")
        
        # Generate detailed reliability reports
        f.write("\n\nRELIABILITY ANALYSIS\n")
        f.write("=" * 30 + "\n")
        
        for test_name, results in all_results.items():
            generate_reliability_report(results, test_name, f)
        
        # Comparative analysis
        f.write("\n\nCOMPARATIVE RELIABILITY\n")
        f.write("=" * 30 + "\n")
        
        for test_name, results in all_results.items():
            direct = results['direct']
            pgbouncer = results['pgbouncer']
            
            if direct and pgbouncer:
                f.write(f"\n{test_name.title()} Test Comparison:\n")
                f.write(f"  Direct Success Rate: {direct['success_rate']:.1f}%\n")
                f.write(f"  PgBouncer Success Rate: {pgbouncer['success_rate']:.1f}%\n")
                f.write(f"  Reliability Improvement: {pgbouncer['success_rate'] - direct['success_rate']:+.1f} percentage points\n")
                
                if direct['connection_rejections'] > pgbouncer['connection_rejections']:
                    f.write(f"  ✅ PgBouncer eliminated {direct['connection_rejections'] - pgbouncer['connection_rejections']} connection rejections\n")
    
    print(f"Detailed analysis complete! Report saved to: {summary_file}")

if __name__ == "__main__":
    main() 