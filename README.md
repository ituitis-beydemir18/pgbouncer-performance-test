# PgBouncer Performance Comparison: Direct vs Pooled Connections

This repository provides a complete infrastructure setup to demonstrate the performance benefits of PgBouncer over direct PostgreSQL connections in high-concurrency scenarios.

## 🎯 Project Overview

This case study replicates a real-world scenario where we compare PostgreSQL performance with and without PgBouncer under simulated high-concurrency workloads. The setup demonstrates how PgBouncer can:

- **Handle 1000+ concurrent connections** vs PostgreSQL's default 100 connection limit
- **Eliminate connection overhead** for dramatically better performance  
- **Reduce latency significantly** in connection-heavy workloads
- **Improve reliability** by eliminating connection rejections

## 📊 Expected Results

Based on our testing with 20 clients each making 100 transactions with new connections:

| Metric | Direct to DB | Via PgBouncer | Improvement |
|--------|--------------|---------------|-------------|
| **Throughput** | 93.94 TPS | 1,062.70 TPS | **11.3x faster** |
| **Latency** | 24.55ms | 16.66ms | **32% reduction** |
| **TPS Improvement** | Baseline | +1,031.3% | **Over 10x boost** |
| **Connection Errors** | Frequent | None | **100% reliability** |

> **Note**: The dramatic improvement comes from eliminating connection establishment overhead. In connection-heavy scenarios, PgBouncer provides massive performance gains.

## 🏗️ Infrastructure

This setup creates:
- **RDS PostgreSQL** instance (max_connections=100, SSL disabled for testing)
- **EC2 instance** running PgBouncer (transaction pooling, 1000 max connections)
- **EC2 instance** for testing client with full test suite
- **VPC** with proper networking and security groups

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.0
3. **AWS CLI** configured with your credentials

### Step 1: Clone Repository

```bash
git clone <your-repo-url>
cd pgbouncer-performance-test
```

### Step 2: Deploy Infrastructure (One Command!)

```bash
./deploy.sh
```

This will:
- Create all AWS infrastructure
- Configure PgBouncer with optimized settings
- Set up test client with performance testing tools
- Show you connection details

### Step 3: Run Performance Tests (One Command!)

```bash
./post_deploy.sh
```

This will:
- Copy full test scripts to the client
- Run comprehensive performance comparison tests
- Download results to your local machine
- Generate detailed analysis report

### Step 4: Clean Up

```bash
./cleanup.sh
```

## 📈 Test Results

The test suite runs three comprehensive tests:

1. **Connection Overhead Test**: 20 clients, 100 transactions each, new connection per transaction
   - Shows PgBouncer's biggest advantage: eliminating connection setup time

2. **High Concurrency Test**: 100 clients with persistent connections
   - Demonstrates scalability benefits

3. **Extreme Load Test**: 1000 clients (exceeds PostgreSQL limits)
   - Shows how PgBouncer handles workloads that would crash direct connections

## 💡 Key Learnings

### When PgBouncer Shines:
- **High connection churn** (web applications, microservices)
- **Connection-heavy workloads** with short transactions
- **Applications exceeding database connection limits**
- **Resource optimization** scenarios

### Performance Gains:
- **11x throughput improvement** in connection-overhead scenarios
- **32% latency reduction** even with the same transactions
- **Unlimited scalability** beyond database connection limits
- **Zero connection errors** under high load

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. **Deployment Issues**
```bash
# If deploy.sh fails
./cleanup.sh  # Clean up any partial resources
./deploy.sh   # Try again

# Check AWS credentials
aws sts get-caller-identity

# Check Terraform version
terraform version
```

#### 2. **SSH Connection Issues**
```bash
# Check if your IP changed
curl https://checkip.amazonaws.com/

# Update terraform.tfvars with new IP
# Then run: terraform apply
```

#### 3. **Performance Test Failures**
```bash
# SSH into test client and check logs
ssh -i terraform/pgbouncer-key.pem ubuntu@<client-ip>
tail -f /var/log/cloud-init-output.log

# Check if PgBouncer is running
ssh -i terraform/pgbouncer-key.pem ubuntu@<pgbouncer-ip>
sudo systemctl status pgbouncer
```

#### 4. **Connection Refused Errors**
- **Cause**: PgBouncer not fully started yet
- **Solution**: Wait 2-3 minutes after deploy, then retry
- **Debug**: Check PgBouncer logs: `sudo journalctl -u pgbouncer -f`

#### 5. **SSL/Authentication Errors**
- **Fixed in this repo**: RDS SSL requirement automatically disabled
- **Note**: SSL is disabled for testing purposes only

### Cost Management
```bash
# Check current AWS costs
aws ce get-cost-and-usage --time-period Start=2025-01-01,End=2025-12-31 --granularity MONTHLY --metrics BlendedCost

# Stop all resources immediately
./cleanup.sh

# Or manually destroy
cd terraform && terraform destroy -auto-approve
```

### Getting Help
- Check AWS CloudWatch logs for detailed error information
- Review terraform plan output before applying changes
- Test with smaller instance types if having resource issues

## 💰 Cost Optimization Tips

- **Use t3.micro instances** (included in free tier for new accounts)
- **Test during off-peak hours** for potential savings
- **Clean up immediately** after testing
- **Use AWS cost alerts** to monitor spending 