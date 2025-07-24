#!/bin/bash

# PgBouncer Performance Test - Post Deployment Automation
# Bu script deploy.sh bittikten sonra çalıştırılır ve tüm test sürecini otomatikleştirir

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script header
echo "==========================================="
echo "PgBouncer Performance Test - Post Deploy"
echo "==========================================="
echo ""

# Change to terraform directory to get outputs
cd terraform

# Check if terraform outputs are available
if ! terraform output > /dev/null 2>&1; then
    log_error "Terraform outputs not available. Make sure deploy.sh completed successfully."
    exit 1
fi

log_info "Getting SSH connection information from terraform..."

# Get SSH connection info
TEST_CLIENT_IP=$(terraform output -raw test_client_public_ip)
SSH_KEY_FILE=$(terraform output -raw ssh_key_file)

if [[ "$SSH_KEY_FILE" == *"pgbouncer-key.pem"* ]]; then
    SSH_KEY_FILE="pgbouncer-key.pem"
    # Make sure key file has correct permissions
    chmod 600 "$SSH_KEY_FILE" 2>/dev/null || true
fi

log_info "Test Client IP: $TEST_CLIENT_IP"
log_info "SSH Key: $SSH_KEY_FILE"

# Verify SSH key exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    log_error "SSH key file not found: $SSH_KEY_FILE"
    log_info "Please make sure your SSH key file is available"
    exit 1
fi

# Function to check if cloud-init is complete
check_cloud_init_status() {
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$TEST_CLIENT_IP" \
        "cloud-init status" 2>/dev/null | grep -q "status: done" && return 0 || return 1
}

# Function to run command via SSH
run_ssh_command() {
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$TEST_CLIENT_IP" "$1"
}

log_info "Connecting to test client and monitoring setup progress..."
echo ""

# Wait for SSH to be available
log_info "Waiting for SSH connection to be available..."
for i in {1..30}; do
    if ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$TEST_CLIENT_IP" "echo 'SSH ready'" > /dev/null 2>&1; then
        log_success "SSH connection established"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "SSH connection timeout. Check your network and security groups."
        exit 1
    fi
    echo -n "."
    sleep 10
done

echo ""

# Monitor cloud-init progress
log_info "Monitoring cloud-init setup progress..."
echo "Checking cloud-init status every 30 seconds..."
echo "You can see the full log output below:"
echo ""

# Start background process to monitor cloud-init status
while true; do
    if check_cloud_init_status; then
        log_success "Cloud-init setup completed!"
        break
    fi
    
    # Show last few lines of cloud-init log
    echo "--- Cloud-init progress (last 10 lines) ---"
    run_ssh_command "sudo tail -10 /var/log/cloud-init-output.log 2>/dev/null || echo 'Log not available yet'"
    echo "--- Waiting 30 seconds for next check ---"
    echo ""
    
    sleep 30
done

echo ""

# Final check of setup
log_info "Verifying setup completion..."
if run_ssh_command "test -f /home/ubuntu/run_performance_test.sh"; then
    log_success "Basic performance test script is available"
else
    log_error "Performance test script not found. Setup may have failed."
    exit 1
fi

echo ""

# Copy full performance test scripts to client
log_info "Uploading full performance test scripts..."

# Copy main performance test script
if [ -f "../scripts/run_performance_test.sh" ]; then
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no "../scripts/run_performance_test.sh" ubuntu@"$TEST_CLIENT_IP":/home/ubuntu/run_performance_test.sh
    log_success "Main performance test script uploaded"
else
    log_error "Main performance test script not found in scripts/ directory"
    exit 1
fi

# Copy analysis script
if [ -f "../scripts/analyze_results_improved.py" ]; then
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no "../scripts/analyze_results_improved.py" ubuntu@"$TEST_CLIENT_IP":/home/ubuntu/analyze_results_improved.py
    log_success "Analysis script uploaded"
else
    log_warning "Analysis script not found, skipping..."
fi

# Copy individual test scripts
if [ -f "../scripts/test_direct_connection.sh" ]; then
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no "../scripts/test_direct_connection.sh" ubuntu@"$TEST_CLIENT_IP":/home/ubuntu/test_direct_connection.sh
    log_success "Direct connection test script uploaded"
fi

if [ -f "../scripts/test_pgbouncer.sh" ]; then
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no "../scripts/test_pgbouncer.sh" ubuntu@"$TEST_CLIENT_IP":/home/ubuntu/test_pgbouncer.sh
    log_success "PgBouncer test script uploaded"
fi

# Make scripts executable
run_ssh_command "chmod +x /home/ubuntu/*.sh /home/ubuntu/*.py" 2>/dev/null || true

log_success "All performance test scripts uploaded and configured"
echo ""

# Run performance tests
log_info "Starting performance tests..."
echo "This will take several minutes to complete..."
echo ""

# Run the performance test and capture output
if run_ssh_command "cd /home/ubuntu && ./run_performance_test.sh" 2>&1 | tee /tmp/test_output.log; then
    log_success "Performance tests completed successfully!"
    TEST_SUCCESS=true
else
    log_warning "Performance tests completed with some issues"
    TEST_SUCCESS=false
fi

echo ""

# Run analysis on remote server
log_info "Running analysis on test client..."
if run_ssh_command "test -f /home/ubuntu/analyze_results_improved.py && test -d /home/ubuntu/test_results"; then
    # Find the timestamp from test results
    REMOTE_TIMESTAMP=$(run_ssh_command "ls /home/ubuntu/test_results/ | grep -E '_(20[0-9]{6}_[0-9]{6})\.log$' | head -1 | sed 's/.*_\(20[0-9]\{6\}_[0-9]\{6\}\)\.log$/\1/'" 2>/dev/null || echo "")
    
    if [ -n "$REMOTE_TIMESTAMP" ]; then
        log_info "Found test timestamp: $REMOTE_TIMESTAMP"
        log_info "Generating performance analysis on remote server..."
        
        # Run analysis on remote server
        if run_ssh_command "cd /home/ubuntu && python3 analyze_results_improved.py test_results $REMOTE_TIMESTAMP"; then
            log_success "Remote analysis completed successfully"
        else
            log_warning "Remote analysis failed, will try local analysis later"
        fi
    else
        log_warning "Could not determine test timestamp for remote analysis"
    fi
else
    log_warning "Analysis script or test results not found on remote server"
fi

echo ""

# Get test results timestamp
log_info "Getting test results..."
TIMESTAMP=$(run_ssh_command "ls /home/ubuntu/test_results/ | grep summary_ | head -1 | sed 's/summary_//g' | sed 's/.txt//g'" 2>/dev/null || echo "")

if [ -z "$TIMESTAMP" ]; then
    log_warning "Could not determine test timestamp, getting latest results..."
    TIMESTAMP="latest"
fi

# Create local results directory
LOCAL_RESULTS_DIR="./test_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOCAL_RESULTS_DIR"

log_info "Downloading test results and analysis to: $LOCAL_RESULTS_DIR"

# Download all test results and analysis
if run_ssh_command "test -d /home/ubuntu/test_results"; then
    # Use scp to download all results
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -r ubuntu@"$TEST_CLIENT_IP":/home/ubuntu/test_results/* "$LOCAL_RESULTS_DIR/" 2>/dev/null || {
        log_warning "SCP download failed, trying alternative method..."
        
        # Alternative: download files one by one
        for file in $(run_ssh_command "ls /home/ubuntu/test_results/"); do
            run_ssh_command "cat /home/ubuntu/test_results/$file" > "$LOCAL_RESULTS_DIR/$file" 2>/dev/null || true
        done
    }
    
    log_success "Test results and analysis downloaded to: $LOCAL_RESULTS_DIR"
else
    log_error "Test results directory not found on remote server"
fi

# Try to run analysis locally if Python is available and results were downloaded
if command -v python3 > /dev/null && ls "$LOCAL_RESULTS_DIR"/summary_*.txt > /dev/null 2>&1; then
    log_info "Running local analysis..."
    if [ -f "scripts/analyze_results_improved.py" ]; then
        # Copy analyze script to results directory and run it
        cp scripts/analyze_results_improved.py "$LOCAL_RESULTS_DIR/"
        cd "$LOCAL_RESULTS_DIR"
        
        # Find the timestamp from downloaded files
        LOCAL_TIMESTAMP=$(ls summary_*.txt 2>/dev/null | head -1 | sed 's/summary_//g' | sed 's/.txt//g' || echo "")
        if [ -n "$LOCAL_TIMESTAMP" ]; then
            python3 analyze_results_improved.py . "$LOCAL_TIMESTAMP" || log_warning "Local analysis failed"
        fi
        cd - > /dev/null
    fi
fi

echo ""
echo "==========================================="
log_success "🎉 Post-deploy automation completed!"
echo "==========================================="
echo ""
echo "Summary:"
echo "✅ Connected to test client: $TEST_CLIENT_IP"
echo "✅ Monitored cloud-init setup completion"
if [ "$TEST_SUCCESS" = true ]; then
    echo "✅ Performance tests completed successfully"
else
    echo "⚠️  Performance tests completed with issues"
fi
echo "✅ Remote analysis generated on test client"
echo "✅ Results and analysis downloaded to: $LOCAL_RESULTS_DIR"
echo ""
echo "Next steps:"
echo "1. Review test results in: $LOCAL_RESULTS_DIR"
echo "2. Check analysis summary: $LOCAL_RESULTS_DIR/summary_*.txt"
echo "3. View individual test logs: $LOCAL_RESULTS_DIR/*.log"
echo "4. When done, clean up AWS resources: ./cleanup.sh"
echo ""
log_warning "💰 Don't forget to run './cleanup.sh' to avoid ongoing AWS charges!"
echo "" 