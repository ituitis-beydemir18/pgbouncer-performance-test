# PgBouncer Performance Test - Detailed Setup Guide

This guide provides step-by-step instructions for setting up and running the PgBouncer performance comparison test.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Manual Setup](#manual-setup)
- [Configuration Options](#configuration-options)
- [Deployment Process](#deployment-process)
- [Post-Deployment Steps](#post-deployment-steps)
- [Running Tests](#running-tests)

## Prerequisites

### Required Software
1. **Terraform** >= 1.0
   - Download from: https://www.terraform.io/downloads.html
   - Verify installation: `terraform version`

2. **AWS CLI** >= 2.0
   - Download from: https://aws.amazon.com/cli/
   - Verify installation: `aws --version`

3. **Git** (to clone the repository)
   - Most systems have this pre-installed
   - Download from: https://git-scm.com/downloads

### AWS Account Setup
1. **AWS Account** with appropriate permissions
   - EC2: Create, describe, terminate instances
   - RDS: Create, describe, delete databases
   - VPC: Create, describe, delete VPCs and related resources
   - IAM: If using roles/policies

2. **AWS Credentials Configuration**
   ```bash
   aws configure
   ```
   You'll need:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., `us-west-2`)
   - Default output format (recommend `json`)

3. **Verify AWS Access**
   ```bash
   aws sts get-caller-identity
   ```

## Quick Start

### Option 1: Automated Deployment (Recommended)
```bash
# Clone the repository
git clone <your-repo-url>
cd pgbouncer-performance-test

# Run the automated deployment script
./deploy.sh
```

The script will:
- Check all prerequisites
- Create configuration files if needed
- Guide you through required settings
- Deploy the infrastructure
- Provide connection information

### Option 2: Manual Steps
If you prefer manual control, follow the [Manual Setup](#manual-setup) section below.

## Manual Setup

### Step 1: Clone Repository
```bash
git clone <your-repo-url>
cd pgbouncer-performance-test
```

### Step 2: Configure Variables
```bash
# Copy the example configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit the configuration file
nano terraform/terraform.tfvars
```

**Required Changes:**
- `your_ip_address`: Your current IP address in CIDR format (e.g., "1.2.3.4/32")
- `db_password`: A secure password for the PostgreSQL database

**Optional Changes:**
- `aws_region`: AWS region for deployment
- `instance_type`: EC2 instance size (affects cost and performance)
- `db_instance_class`: RDS instance size

### Step 3: Get Your IP Address
You need your current public IP address for SSH access:
```bash
# Option 1: Use a web service
curl https://ipinfo.io/ip

# Option 2: Visit https://whatismyipaddress.com/

# Add "/32" to the end for CIDR format
# Example: if your IP is 203.0.113.1, use "203.0.113.1/32"
```

### Step 4: Deploy Infrastructure
```bash
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the changes
terraform apply
```

## Configuration Options

### terraform.tfvars Configuration

```hcl
# AWS Configuration
aws_region = "us-west-2"                # AWS region
availability_zone = "us-west-2a"        # Primary AZ
availability_zone_secondary = "us-west-2b"  # Secondary AZ for RDS

# Security Configuration
your_ip_address = "YOUR.IP.ADDRESS/32"  # Your IP for SSH access

# SSH Key Configuration
public_key = ""  # Leave empty to auto-generate SSH keys

# Database Configuration
db_name = "testdb"                      # Database name
db_username = "postgres"                # Database username
db_password = "YourSecurePassword123!"  # Database password (CHANGE THIS!)

# Instance Configuration
instance_type = "t3.micro"              # EC2 instance type
db_instance_class = "db.t3.micro"       # RDS instance class
```

### Instance Size Options

#### For Cost Optimization (Default)
```hcl
instance_type = "t3.micro"       # ~$8.5/month each
db_instance_class = "db.t3.micro"  # ~$13/month
```

#### For Better Performance
```hcl
instance_type = "t3.medium"      # ~$30/month each
db_instance_class = "db.t3.small"  # ~$26/month
```

#### For Production-Like Testing
```hcl
instance_type = "t3.large"       # ~$60/month each
db_instance_class = "db.t3.medium" # ~$52/month
```

### PgBouncer Configuration

The default PgBouncer configuration is optimized for performance testing:

```ini
# Pool settings
pool_mode = transaction          # Best performance
max_client_conn = 1000          # Support high concurrency
default_pool_size = 100         # Reasonable DB connection limit
min_pool_size = 25              # Always-ready connections
reserve_pool_size = 25          # Emergency connections
```

To modify PgBouncer settings, edit `config/pgbouncer.ini` before deployment.

## Deployment Process

### What Gets Created

The deployment creates:

1. **VPC Infrastructure**
   - VPC with public and private subnets
   - Internet Gateway
   - Route tables and security groups

2. **RDS PostgreSQL Database**
   - Instance in private subnet
   - max_connections = 100 (for testing limits)
   - Standard pgbench schema and data

3. **PgBouncer Server (EC2)**
   - Installs and configures PgBouncer
   - Connects to RDS database
   - Transaction pooling mode
   - Monitoring and test scripts

4. **Test Client (EC2)**
   - PostgreSQL client tools
   - Performance test scripts
   - Python analysis tools

5. **SSH Key Pair**
   - Auto-generated if not provided
   - Used for EC2 access

### Deployment Timeline

- **Terraform Planning**: 1-2 minutes
- **Infrastructure Creation**: 8-12 minutes
- **Instance Initialization**: 3-5 minutes
- **Total Time**: ~15-20 minutes

### Monitoring Deployment

```bash
# Check overall status
./status.sh

# Check Terraform state
cd terraform && terraform show

# Monitor instance initialization (after SSH)
tail -f /var/log/cloud-init-output.log
```

## Post-Deployment Steps

### 1. Verify Connectivity
```bash
# Check infrastructure status
./status.sh

# Test SSH connections (use provided commands from terraform output)
ssh -i terraform/pgbouncer-key.pem ubuntu@<client-ip>
```

### 2. Wait for Setup Completion
```bash
# On the test client, monitor setup progress
tail -f /var/log/cloud-init-output.log

# Look for "Setup complete!" message
# This usually takes 2-3 minutes after instance startup
```

### 3. Verify Database Connectivity
```bash
# On test client
./test_direct_connection.sh    # Test direct DB connection
./test_pgbouncer.sh           # Test PgBouncer connection
```

## Running Tests

### Quick Test
```bash
# SSH into test client
ssh -i terraform/pgbouncer-key.pem ubuntu@<client-ip>

# Run individual connection tests
./test_direct_connection.sh
./test_pgbouncer.sh
```

### Full Performance Comparison
```bash
# Run the complete test suite
./run_performance_test.sh

# This runs three test scenarios:
# 1. Connection overhead test (20 clients, new connection per transaction)
# 2. High concurrency test (100 clients, persistent connections)
# 3. Extreme load test (1000 clients - direct should fail)
```

### Test Output
Results are saved to `~/test_results/` with timestamps:
- Individual test logs
- Summary analysis
- Detailed performance comparison

### Viewing Results
```bash
# View summary
cat ~/test_results/summary_TIMESTAMP.txt

# View detailed analysis
cat ~/test_results/detailed_analysis_TIMESTAMP.txt

# Check specific metrics
grep "tps =" ~/test_results/*.log
grep "latency average" ~/test_results/*.log
```

## Common Issues and Solutions

### SSH Connection Issues
- Verify your IP address in terraform.tfvars
- Check security group settings
- Ensure key file permissions: `chmod 600 terraform/pgbouncer-key.pem`

### Database Connection Issues
- Wait for RDS to reach "available" status (check with `./status.sh`)
- Verify PgBouncer is running: `sudo systemctl status pgbouncer`
- Check logs: `sudo journalctl -u pgbouncer -f`

### Performance Test Issues
- Ensure all services are running
- Check database has test data: `\dt` in psql
- Monitor system resources during tests: `htop`

## Cost Management

### Expected Costs (if left running)
- **RDS db.t3.micro**: ~$0.43/day
- **2x EC2 t3.micro**: ~$0.56/day
- **Total**: ~$1.00/day (~$30/month)

### Cost Optimization
1. **Use t3.micro instances** for basic testing
2. **Run tests and cleanup immediately**
3. **Use spot instances** for extended testing (requires Terraform modification)

### Cleanup
```bash
# Destroy all resources when done
./cleanup.sh

# This stops all AWS charges for the test infrastructure
```

## Next Steps

After successful deployment:
1. [Run performance tests](RESULTS_ANALYSIS.md)
2. [Understand the results](RESULTS_ANALYSIS.md)
3. [Troubleshoot issues](TROUBLESHOOTING.md)
4. [Customize the setup](#configuration-options) for your needs

## Support

For issues not covered in this guide:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review Terraform and AWS documentation
3. Check AWS CloudWatch logs for detailed error information 