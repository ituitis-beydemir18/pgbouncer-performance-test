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

## 🛠 Prerequisites

- **AWS Account with appropriate permissions**  
  You need to create an [AWS account](https://aws.amazon.com/). To get started quickly, you can assign `AdministratorAccess` to the user, but this is **not recommended for production** environments due to security risks.  
  🔗 [Create an IAM User Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html)

- **Terraform >= 1.0**  
  Make sure Terraform version 1.0 or higher is installed on your system.  
  🔗 [Terraform Download Page](https://developer.hashicorp.com/terraform/downloads)

- **AWS CLI configured with your credentials**  
  Install the AWS CLI and run `aws configure` to provide your access credentials.  
  🔗 [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)  
  🔗 [Create AWS Access Keys Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html)

## 🔧 Main Scripts

| Script | Purpose |
|--------|---------|
| `./deploy.sh` | Deploy infrastructure (RDS, EC2, PgBouncer setup) |
| `./post_deploy.sh` | Run tests and download results locally |
| `./cleanup.sh` | Destroy all AWS resources |

## 📊 Test Results & Analysis

After running tests, you'll get local files with:
- **Performance metrics**: TPS, latency, throughput comparisons
- **Reliability metrics**: Success rates, connection rejections, timeouts
- **Detailed logs**: Individual pgbench outputs for each test scenario
- **Summary reports**: Comprehensive analysis with recommendations

## 🧪 Test Cases & Metrics

| Test Case | Scenario | Metrics Measured |
|-----------|----------|------------------|
| **Connection Overhead** | 20 clients, new connection per transaction | Connection setup time, TPS |
| **High Concurrency** | 80 clients, persistent connections | Scalability limits, resource contention |
| **Extreme Load** | 1000 clients, exceeds DB limits | Connection rejections, queue handling |

**Reliability Metrics:**
- Success/Error rates
- Connection rejection counts  
- Timeout rates
- Error type classification
- Performance consistency

## 🧹 Test Isolation & Cleanup

To ensure fair comparison, **full cleanup** runs between each test phase:
- Database statistics reset
- PgBouncer connection pool reset
- OS cache clearing
- TCP connection settling (35-second intervals)

This eliminates contamination effects like warm caches or pre-established connections.

## 🏗️ Test Architecture

```
[Test Client EC2] ──direct──→ [RDS PostgreSQL]
      │                              ↑
      └─────→ [PgBouncer EC2] ────────┘
```

**Infrastructure:**
- **Test Client**: Runs pgbench, generates load
- **PgBouncer Server**: Connection pooling, transaction mode
- **RDS PostgreSQL**: Target database (max_connections=100)

**Test Flow:**
1. Client sends direct requests to RDS
2. Client sends requests through PgBouncer to RDS  
3. Metrics compared for same workload patterns

## 📁 Project Structure

```
pgbouncer-performance-test/
├── scripts/
│   ├── run_performance_test.sh      # Main test execution script
│   ├── analyze_results_improved.py  # Detailed metrics analysis
│   ├── test_direct_connection.sh    # Direct DB connection tests
│   └── test_pgbouncer.sh           # PgBouncer connection tests
├── terraform/
│   ├── main.tf                     # Infrastructure definitions
│   ├── variables.tf                # Configuration variables
│   ├── outputs.tf                  # Infrastructure outputs
│   └── user-data/                  # EC2 setup scripts
├── docs/                           # Documentation and guides
├── deploy.sh                       # Infrastructure deployment
├── post_deploy.sh                  # Test execution & results
└── cleanup.sh                      # Resource cleanup
```

## 🚀 Quick Start

```bash
# 1. Clone and setup
git clone <repo-url>
cd pgbouncer-performance-test

# 2. Deploy infrastructure (~15 minutes)
./deploy.sh

# 3. Run tests and get results (~15 minutes)
./post_deploy.sh

# 4. Clean up when done
./cleanup.sh
```

## 📈 Expected Results

| Scenario | Direct DB | PgBouncer | Improvement |
|----------|-----------|-----------|-------------|
| **Connection Overhead** | ~100 TPS | ~800 TPS | **8x faster** |
| **High Concurrency** | ~200 TPS | ~600 TPS | **3x faster** |  
| **Extreme Load** | **FAILS** | ~400 TPS | **100% success** |

## 💡 Key Benefits

- **Eliminates connection overhead** for massive performance gains
- **Handles 1000+ concurrent connections** vs PostgreSQL's 100 limit
- **Provides reliable connection pooling** and queuing
- **Reduces latency and increases throughput** consistently

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