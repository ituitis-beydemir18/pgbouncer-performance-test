#!/bin/bash

# PgBouncer Performance Test - Deployment Script
# This script automates the deployment of the test infrastructure

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
echo "PgBouncer Performance Test Deployment"
echo "======================================"
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed. Please install Terraform >= 1.0"
    echo "Installation guide: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

# Check terraform version
TERRAFORM_VERSION=$(terraform version -json | grep '"version"' | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')
log_info "Found Terraform version: $TERRAFORM_VERSION"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install and configure AWS CLI"
    echo "Installation guide: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure'"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
log_info "AWS Account: $AWS_ACCOUNT"
log_info "AWS Region: $AWS_REGION"

log_success "All prerequisites met!"
echo ""

# Check if terraform.tfvars exists
TFVARS_FILE="terraform/terraform.tfvars"
TFVARS_EXAMPLE="terraform/terraform.tfvars.example"

if [ ! -f "$TFVARS_FILE" ]; then
    log_warning "terraform.tfvars not found"
    log_info "Auto-generating terraform.tfvars with optimal settings..."
    
    # Get user's current public IP
    log_info "Detecting your public IP address..."
    USER_IP=$(curl -s https://checkip.amazonaws.com/ )
    
    if [ -z "$USER_IP" ]; then
        log_error "Could not detect your IP address. Please check your internet connection."
        exit 1
    fi
    
    log_success "Detected IP: $USER_IP"
    
    # Generate a secure password
    log_info "Generating secure database password..."
    if command -v openssl &> /dev/null; then
        DB_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
    else
        # Fallback password generation
        DB_PASSWORD="PgBouncer$(date +%s | tail -c 4)Test!"
    fi
    
    # Use detected AWS region or default to us-west-2
    REGION=${AWS_REGION:-"us-west-2"}
    
    # Create terraform.tfvars with auto-detected values
    cat > "$TFVARS_FILE" << EOF
# AWS Configuration
aws_region = "$REGION"
availability_zone = "${REGION}a"

# Your IP for SSH access (auto-detected)
your_ip_address = "$USER_IP/32"

# Database Configuration
db_name = "testdb"
db_username = "postgres"
db_password = "$DB_PASSWORD"

# Instance Configuration
instance_type = "t3.micro"  # Minimal cost for testing
db_instance_class = "db.t3.micro"  # Minimal cost for testing
EOF

    log_success "Created terraform.tfvars with auto-detected settings:"
    echo "  - Your IP: $USER_IP/32"
    echo "  - AWS Region: $REGION"
    echo "  - Database Password: $DB_PASSWORD"
    echo "  - Instance Type: t3.micro (cost-optimized)"
    echo ""
    log_info "You can edit $TFVARS_FILE if you want to change any settings"
    
    echo ""
    read -p "Have you updated the configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Please update the configuration and run this script again"
        exit 1
    fi
fi

log_success "Configuration file found: $TFVARS_FILE"
echo ""

# Validate key settings in terraform.tfvars
log_info "Validating configuration..."

if grep -q "1.2.3.4/32" "$TFVARS_FILE"; then
    log_error "Please update your_ip_address in $TFVARS_FILE"
    log_info "Get your IP from: https://whatismyipaddress.com/"
    exit 1
fi

if grep -q "YourSecurePassword123!" "$TFVARS_FILE"; then
    log_warning "Please change the default database password in $TFVARS_FILE"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log_success "Configuration validation passed"
echo ""

# Change to terraform directory
cd terraform

# Initialize Terraform
log_info "Initializing Terraform..."
if terraform init; then
    log_success "Terraform initialized successfully"
else
    log_error "Terraform initialization failed"
    exit 1
fi

echo ""

# Plan deployment
log_info "Creating deployment plan..."
if terraform plan -out=tfplan; then
    log_success "Deployment plan created successfully"
else
    log_error "Deployment planning failed"
    exit 1
fi

echo ""

# Show cost estimate
log_warning "💰 Cost Estimate:"
echo "If left running 24/7:"
echo "- RDS db.t3.micro: ~$13/month"
echo "- 2x EC2 t3.micro: ~$17/month"
echo "- Total: ~$30/month"
echo ""
echo "💡 Remember to run './cleanup.sh' when done testing!"
echo ""

# Confirm deployment
read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled"
    exit 0
fi

# Apply deployment
log_info "Starting deployment..."
echo "This may take 10-15 minutes to complete..."
echo ""

START_TIME=$(date +%s)

if terraform apply tfplan; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log_success "🎉 Deployment completed successfully in ${DURATION}s!"
else
    log_error "Deployment failed"
    exit 1
fi

echo ""

# Show outputs
log_info "Deployment Information:"
terraform output

echo ""

# Final instructions
log_success "🚀 Infrastructure deployed successfully!"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for instances to complete setup"
echo "2. SSH into the test client using the provided commands"
echo "3. Run the performance tests:"
echo "   ./run_performance_test.sh"
echo ""
echo "Monitoring commands:"
echo "- Check setup progress: tail -f /var/log/cloud-init-output.log"
echo "- Monitor PgBouncer: ./monitor_pgbouncer.sh (on PgBouncer server)"
echo ""
echo "⚠️  Don't forget to clean up when done:"
echo "   ./cleanup.sh"
echo ""
log_success "Happy testing! 🎯" 