#!/bin/bash

# PgBouncer Performance Test - Status Check Script
# This script checks the status of deployed infrastructure and services

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
echo "PgBouncer Performance Test Status"
echo "======================================"
echo ""

# Check if terraform directory exists
if [ ! -d "terraform" ]; then
    log_error "terraform directory not found. Are you in the right directory?"
    exit 1
fi

# Check if terraform is initialized
if [ ! -d "terraform/.terraform" ]; then
    log_error "Terraform not initialized. Run './deploy.sh' first."
    exit 1
fi

# Change to terraform directory
cd terraform

# Check if infrastructure is deployed
log_info "Checking infrastructure status..."

if [ ! -f "terraform.tfstate" ] || [ ! -s "terraform.tfstate" ]; then
    log_warning "No infrastructure found. Run './deploy.sh' to create resources."
    exit 0
fi

# Get terraform outputs
if ! terraform output > /dev/null 2>&1; then
    log_error "Unable to read terraform outputs. Infrastructure may be in an inconsistent state."
    exit 1
fi

# Extract key information
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "unknown")
PGBOUNCER_IP=$(terraform output -raw pgbouncer_public_ip 2>/dev/null || echo "unknown")
CLIENT_IP=$(terraform output -raw test_client_public_ip 2>/dev/null || echo "unknown")

echo "Infrastructure Overview:"
echo "========================"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "PgBouncer Server: $PGBOUNCER_IP"
echo "Test Client: $CLIENT_IP"
echo ""

# Check AWS CLI availability
if ! command -v aws &> /dev/null; then
    log_warning "AWS CLI not available. Cannot check detailed instance status."
    echo ""
    terraform output
    exit 0
fi

# Check EC2 instance status
log_info "Checking EC2 instance status..."

# Get instance IDs
PGBOUNCER_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pgbouncer-server" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")

CLIENT_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=pgbouncer-test-client" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")

if [ "$PGBOUNCER_INSTANCE_ID" != "None" ] && [ "$PGBOUNCER_INSTANCE_ID" != "null" ]; then
    PGBOUNCER_STATE=$(aws ec2 describe-instances --instance-ids "$PGBOUNCER_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)
    echo "PgBouncer Server ($PGBOUNCER_INSTANCE_ID): $PGBOUNCER_STATE"
else
    echo "PgBouncer Server: Not found"
fi

if [ "$CLIENT_INSTANCE_ID" != "None" ] && [ "$CLIENT_INSTANCE_ID" != "null" ]; then
    CLIENT_STATE=$(aws ec2 describe-instances --instance-ids "$CLIENT_INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)
    echo "Test Client ($CLIENT_INSTANCE_ID): $CLIENT_STATE"
else
    echo "Test Client: Not found"
fi

echo ""

# Check RDS status
log_info "Checking RDS status..."

RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pgbouncer-test-db \
    --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "not-found")

echo "RDS PostgreSQL: $RDS_STATUS"
echo ""

# Connectivity tests
if [ "$PGBOUNCER_IP" != "unknown" ] && [ "$CLIENT_IP" != "unknown" ]; then
    log_info "Testing connectivity..."
    
    # Test SSH connectivity to test client
    if timeout 5 bash -c "echo >/dev/tcp/$CLIENT_IP/22" 2>/dev/null; then
        echo "✅ SSH to test client: Available"
    else
        echo "❌ SSH to test client: Not available"
    fi
    
    # Test SSH connectivity to PgBouncer server
    if timeout 5 bash -c "echo >/dev/tcp/$PGBOUNCER_IP/22" 2>/dev/null; then
        echo "✅ SSH to PgBouncer server: Available"
    else
        echo "❌ SSH to PgBouncer server: Not available"
    fi
    
    echo ""
fi

# Show connection commands
log_info "Connection Commands:"
echo "==================="

if [ -f "pgbouncer-key.pem" ]; then
    echo "SSH to test client:"
    echo "  ssh -i terraform/pgbouncer-key.pem ubuntu@$CLIENT_IP"
    echo ""
    echo "SSH to PgBouncer server:"
    echo "  ssh -i terraform/pgbouncer-key.pem ubuntu@$PGBOUNCER_IP"
else
    echo "SSH to test client:"
    echo "  ssh -i your-private-key.pem ubuntu@$CLIENT_IP"
    echo ""
    echo "SSH to PgBouncer server:"
    echo "  ssh -i your-private-key.pem ubuntu@$PGBOUNCER_IP"
fi

echo ""

# Show test commands
log_info "Test Commands (run on test client):"
echo "===================================="
echo "Check setup progress:"
echo "  tail -f /var/log/cloud-init-output.log"
echo ""
echo "Run performance tests:"
echo "  ./run_performance_test.sh"
echo ""
echo "Individual tests:"
echo "  ./test_direct_connection.sh"
echo "  ./test_pgbouncer.sh"
echo ""

# Show monitoring commands
log_info "Monitoring Commands:"
echo "==================="
echo "Monitor PgBouncer (on PgBouncer server):"
echo "  ./monitor_pgbouncer.sh"
echo ""
echo "Check PgBouncer logs:"
echo "  sudo journalctl -u pgbouncer -f"
echo ""
echo "Check system resources:"
echo "  htop"
echo "  iostat 1"
echo ""

# Cost reminder
log_warning "💰 Cost Reminder:"
echo "Your infrastructure is currently incurring charges:"
echo "- RDS db.t3.micro: ~$0.43/day"
echo "- 2x EC2 t3.micro: ~$0.56/day"
echo "- Total: ~$1.00/day"
echo ""
echo "Run './cleanup.sh' when you're done testing!"
echo ""

# Final status summary
echo "======================================"
if [ "$RDS_STATUS" = "available" ] && [ "$PGBOUNCER_STATE" = "running" ] && [ "$CLIENT_STATE" = "running" ]; then
    log_success "🎉 All systems are running and ready for testing!"
elif [ "$RDS_STATUS" = "available" ] || [ "$PGBOUNCER_STATE" = "running" ] || [ "$CLIENT_STATE" = "running" ]; then
    log_warning "⚠️  Some systems are still starting up. Wait a few minutes and check again."
else
    log_error "❌ Systems are not ready. Check the AWS console for issues."
fi
echo "======================================" 