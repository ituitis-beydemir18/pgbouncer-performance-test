#!/bin/bash

# PgBouncer Performance Test - Cleanup Script
# This script destroys all test infrastructure to avoid ongoing costs

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
echo "PgBouncer Performance Test Cleanup"
echo "======================================"
echo ""

# Check if terraform directory exists
if [ ! -d "terraform" ]; then
    log_error "terraform directory not found. Are you in the right directory?"
    exit 1
fi

# Check if terraform is initialized
if [ ! -d "terraform/.terraform" ]; then
    log_error "Terraform not initialized. Run './deploy.sh' first or 'terraform init' in terraform/ directory"
    exit 1
fi

# Change to terraform directory
cd terraform

# Check if there are resources to destroy
log_info "Checking for deployed resources..."

if ! terraform plan -destroy > /dev/null 2>&1; then
    log_error "Unable to create destroy plan. Check your AWS credentials and configuration."
    exit 1
fi

# Count resources to destroy
RESOURCE_COUNT=$(terraform plan -destroy 2>/dev/null | grep -c "will be destroyed" || echo "0")

if [ "$RESOURCE_COUNT" = "0" ]; then
    log_info "No resources found to destroy. Infrastructure may already be cleaned up."
    exit 0
fi

log_warning "Found $RESOURCE_COUNT resources to destroy"

# Show what will be destroyed
echo ""
log_info "Resources that will be destroyed:"
terraform plan -destroy | grep "will be destroyed" | sed 's/.*# /  - /' | sed 's/ will be destroyed.*//'

echo ""

# Warning about data loss
log_warning "⚠️  WARNING: This will permanently destroy all test infrastructure!"
echo ""
echo "This includes:"
echo "- EC2 instances (PgBouncer server and test client)"
echo "- RDS PostgreSQL database (and all data)"
echo "- VPC and networking components"
echo "- SSH key pairs"
echo ""
echo "💾 If you have important test results, make sure to download them first!"
echo ""

# Cost savings info
log_info "💰 After cleanup, you will stop incurring AWS charges for:"
echo "- RDS instance: ~$13/month"
echo "- EC2 instances: ~$17/month" 
echo "- Total savings: ~$30/month"
echo ""

# Double confirmation
read -p "Are you absolutely sure you want to destroy everything? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Cleanup cancelled. Your infrastructure is still running."
    echo ""
    log_warning "💡 Remember: AWS resources continue to incur charges while running."
    exit 0
fi

# Final warning
echo ""
log_warning "🚨 LAST CHANCE: This action cannot be undone!"
read -p "Proceed with destruction? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

# Start destruction
log_info "Starting infrastructure destruction..."
echo "This may take 5-10 minutes to complete..."
echo ""

START_TIME=$(date +%s)

if terraform destroy -auto-approve; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log_success "🎉 Infrastructure destroyed successfully in ${DURATION}s!"
else
    log_error "Destruction failed. Some resources may still exist."
    echo ""
    log_warning "Check the AWS console and try running this script again."
    exit 1
fi

echo ""

# Cleanup local files
log_info "Cleaning up local files..."

# Remove terraform state backup files (keep main state for safety)
rm -f terraform.tfstate.backup
rm -f tfplan

# Remove generated SSH key if it exists
if [ -f "pgbouncer-key.pem" ]; then
    rm -f pgbouncer-key.pem
    log_info "Removed generated SSH key"
fi

log_success "Local cleanup completed"

echo ""

# Final message
log_success "🧹 Cleanup completed successfully!"
echo ""
echo "✅ All AWS resources have been destroyed"
echo "✅ You are no longer being charged for test infrastructure"
echo "✅ Local temporary files have been cleaned up"
echo ""
log_info "You can safely re-deploy anytime by running './deploy.sh'"
echo ""
log_success "Thank you for testing PgBouncer performance! 🚀" 