#!/bin/bash

# Auto Test Runner - Run after deployment completes
# This script automatically connects to test client, runs tests, and downloads results

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
echo "======================================"
echo "PgBouncer Auto Test Runner"
echo "======================================"
echo ""

# Check if terraform directory exists and is deployed
if [ ! -d "terraform" ]; then
    log_error "terraform directory not found. Are you in the right directory?"
    exit 1
fi

if [ ! -f "terraform/terraform.tfstate" ] || [ ! -s "terraform/terraform.tfstate" ]; then
    log_error "No terraform state found. Run ./deploy.sh first!"
    exit 1
fi

cd terraform

# Get deployment information from terraform
log_info "Getting deployment information..."

if ! terraform output > /dev/null 2>&1; then
    log_error "Unable to read terraform outputs. Deployment may have failed."
    exit 1
fi

TEST_CLIENT_IP=$(terraform output -raw test_client_public_ip 2>/dev/null)
SSH_KEY_FILE=$(terraform output -raw ssh_key_file 2>/dev/null)

if [ -z "$TEST_CLIENT_IP" ]; then
    log_error "Could not get test client IP from terraform output"
    exit 1
fi

# Determine SSH key file path
if [[ "$SSH_KEY_FILE" == *"pgbouncer-key.pem" ]]; then
    SSH_KEY_PATH="pgbouncer-key.pem"
else
    SSH_KEY_PATH="$SSH_KEY_FILE"
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    log_error "SSH key file not found: $SSH_KEY_PATH"
    exit 1
fi

# Ensure correct permissions on SSH key
chmod 600 "$SSH_KEY_PATH"

log_success "Found test client: $TEST_CLIENT_IP"
log_success "Using SSH key: $SSH_KEY_PATH"

cd ..

# SSH connection details
SSH_CMD="ssh -i terraform/$SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$TEST_CLIENT_IP"

# Wait for SSH to be available
log_info "Waiting for SSH connection to be available..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if $SSH_CMD "echo 'SSH connected'" > /dev/null 2>&1; then
        log_success "SSH connection established!"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_info "SSH attempt $RETRY_COUNT/$MAX_RETRIES... waiting 10 seconds"
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "Could not establish SSH connection after $MAX_RETRIES attempts"
    log_error "Try running: ssh -i terraform/$SSH_KEY_PATH ubuntu@$TEST_CLIENT_IP"
    exit 1
fi

# Check if setup is complete
log_info "Checking if instance setup is complete..."

# Function to check setup status
check_setup_complete() {
    $SSH_CMD "grep -q 'Setup complete!' /var/log/cloud-init-output.log 2>/dev/null"
}

# Wait for setup to complete
log_info "Waiting for instance initialization to complete..."
echo "This may take 2-5 minutes for package installation..."

SETUP_TIMEOUT=600  # 10 minutes timeout
SETUP_START=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - SETUP_START))
    
    if [ $ELAPSED -gt $SETUP_TIMEOUT ]; then
        log_error "Setup timeout after $SETUP_TIMEOUT seconds"
        log_warning "You can check setup progress manually:"
        log_warning "  ssh -i terraform/$SSH_KEY_PATH ubuntu@$TEST_CLIENT_IP"
        log_warning "  tail -f /var/log/cloud-init-output.log"
        exit 1
    fi
    
    if check_setup_complete; then
        log_success "Instance setup completed!"
        break
    fi
    
    # Show progress every 30 seconds
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        log_info "Still waiting for setup... (${ELAPSED}s elapsed)"
        # Show last few lines of setup log
        $SSH_CMD "tail -3 /var/log/cloud-init-output.log 2>/dev/null | grep -v '^$'" || true
    fi
    
    sleep 10
done

# Brief pause to ensure everything is ready
sleep 5

# Run performance tests
log_info "Starting performance tests..."
echo "This will run 3 test scenarios and may take 10-15 minutes..."

# Create timestamp for this test run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Run the performance test
log_info "Running performance test suite..."
if $SSH_CMD "./run_performance_test.sh" 2>&1 | tee "test_output_$TIMESTAMP.log"; then
    log_success "Performance tests completed!"
else
    log_error "Performance tests failed. Check the output above."
    log_warning "You can connect manually to investigate:"
    log_warning "  ssh -i terraform/$SSH_KEY_PATH ubuntu@$TEST_CLIENT_IP"
    exit 1
fi

# Try to run Python analysis if it didn't work automatically
log_info "Checking if analysis was generated..."

# Get the latest timestamp from the remote system
REMOTE_TIMESTAMP=$($SSH_CMD "ls ~/test_results/summary_*.txt 2>/dev/null | head -1 | sed 's/.*summary_\\([0-9_]*\\)\\.txt/\\1/'" || echo "")

if [ -z "$REMOTE_TIMESTAMP" ]; then
    log_warning "No summary found. Attempting to run analysis..."
    
    # Try to find any log files and run analysis
    if $SSH_CMD "ls ~/test_results/*.log > /dev/null 2>&1"; then
        LATEST_LOG=$($SSH_CMD "ls ~/test_results/*.log | head -1")
        if [ -n "$LATEST_LOG" ]; then
            # Extract timestamp from log filename
            REMOTE_TIMESTAMP=$(echo "$LATEST_LOG" | sed 's/.*_\\([0-9_]*\\)\\.log/\\1/')
            
            log_info "Running Python analysis for timestamp: $REMOTE_TIMESTAMP"
            $SSH_CMD "cd ~ && python3 analyze_results.py test_results/ $REMOTE_TIMESTAMP" || log_warning "Python analysis failed, but test results are available"
        fi
    fi
fi

# Download results
log_info "Downloading test results to local machine..."

# Create local results directory
LOCAL_RESULTS_DIR="test_results_$TIMESTAMP"
mkdir -p "$LOCAL_RESULTS_DIR"

# Download all test results
if $SSH_CMD "ls ~/test_results/ > /dev/null 2>&1"; then
    scp -i "terraform/$SSH_KEY_PATH" -o StrictHostKeyChecking=no -r "ubuntu@$TEST_CLIENT_IP:~/test_results/*" "$LOCAL_RESULTS_DIR/" 2>/dev/null || {
        log_warning "SCP failed, trying alternative method..."
        
        # Try downloading individual files
        for file in summary direct_overhead pgbouncer_overhead direct_concurrent pgbouncer_concurrent direct_extreme pgbouncer_extreme; do
            $SSH_CMD "ls ~/test_results/${file}_*.* 2>/dev/null" | while read remote_file; do
                if [ -n "$remote_file" ]; then
                    local_file=$(basename "$remote_file")
                    scp -i "terraform/$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ubuntu@$TEST_CLIENT_IP:$remote_file" "$LOCAL_RESULTS_DIR/$local_file" 2>/dev/null || true
                fi
            done
        done
    }
    
    log_success "Test results downloaded to: $LOCAL_RESULTS_DIR/"
else
    log_warning "No test results found on remote system"
fi

# Show summary if available
if [ -f "$LOCAL_RESULTS_DIR/summary_"*".txt" ]; then
    SUMMARY_FILE=$(ls "$LOCAL_RESULTS_DIR/summary_"*".txt" | head -1)
    log_success "Test Summary:"
    echo "=========================="
    cat "$SUMMARY_FILE"
    echo "=========================="
else
    log_warning "No summary file found. Check individual log files in $LOCAL_RESULTS_DIR/"
fi

# Final instructions
echo ""
log_success "🎉 Auto test completed successfully!"
echo ""
echo "📁 Results location: $LOCAL_RESULTS_DIR/"
echo "📊 Available files:"
ls -la "$LOCAL_RESULTS_DIR/" 2>/dev/null || echo "  (No files downloaded)"
echo ""
echo "🔗 SSH connection (if needed):"
echo "  ssh -i terraform/$SSH_KEY_PATH ubuntu@$TEST_CLIENT_IP"
echo ""
echo "💰 Don't forget to cleanup when done:"
echo "  ./cleanup.sh"
echo ""
echo "======================================" 