# PgBouncer Performance Test - Troubleshooting Guide

This guide helps resolve common issues you might encounter during deployment, configuration, or testing.

## Table of Contents
- [Prerequisites Issues](#prerequisites-issues)
- [Configuration Issues](#configuration-issues)
- [Deployment Issues](#deployment-issues)
- [Connectivity Issues](#connectivity-issues)
- [PgBouncer Issues](#pgbouncer-issues)
- [Performance Test Issues](#performance-test-issues)
- [AWS-Specific Issues](#aws-specific-issues)
- [General Debugging](#general-debugging)

## Prerequisites Issues

### Terraform Not Found
**Error**: `terraform: command not found`

**Solution**:
1. Install Terraform from https://www.terraform.io/downloads.html
2. Add to PATH or use full path
3. Verify: `terraform version`

**Alternative**: Use Docker
```bash
docker run --rm -v $(pwd):/workspace -w /workspace hashicorp/terraform:latest version
```

### AWS CLI Issues
**Error**: `aws: command not found` or credential errors

**Solutions**:
1. **Install AWS CLI**: https://aws.amazon.com/cli/
2. **Configure credentials**:
   ```bash
   aws configure
   ```
3. **Verify access**:
   ```bash
   aws sts get-caller-identity
   ```
4. **Check permissions**: Ensure your AWS user has EC2, RDS, and VPC permissions

### AWS Credentials Problems
**Error**: `Unable to locate credentials`

**Solutions**:
1. **Environment variables**:
   ```bash
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_DEFAULT_REGION=us-west-2
   ```

2. **AWS credentials file** (`~/.aws/credentials`):
   ```ini
   [default]
   aws_access_key_id = your_access_key
   aws_secret_access_key = your_secret_key
   ```

3. **IAM role** (if running on EC2):
   - Attach appropriate IAM role to your EC2 instance

## Configuration Issues

### IP Address Format
**Error**: IP validation failed in terraform.tfvars

**Solution**: Use CIDR format
```bash
# Wrong
your_ip_address = "203.0.113.1"

# Correct
your_ip_address = "203.0.113.1/32"
```

**Get your IP**:
```bash
curl https://ipinfo.io/ip
# Add /32 to the result
```

### Database Password Requirements
**Error**: Password validation failed

**Requirements**:
- Minimum 8 characters
- Avoid special characters that might break shell scripts
- Use quotes in terraform.tfvars: `db_password = "MyPassword123"`

### Region/AZ Mismatch
**Error**: Availability zone not found

**Solution**: Ensure consistency
```hcl
aws_region = "us-west-2"
availability_zone = "us-west-2a"           # Must be in us-west-2
availability_zone_secondary = "us-west-2b" # Must be in us-west-2
```

**List available AZs**:
```bash
aws ec2 describe-availability-zones --region us-west-2
```

## Deployment Issues

### Terraform Init Failures
**Error**: Plugin installation failed

**Solutions**:
1. **Check internet connectivity**
2. **Clear Terraform cache**:
   ```bash
   rm -rf .terraform/
   terraform init
   ```
3. **Use specific provider version**:
   ```hcl
   terraform {
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "= 5.31.0"  # Specific version
       }
     }
   }
   ```

### Resource Limits
**Error**: Resource limit exceeded

**Common limits**:
- VPCs per region: 5
- EC2 instances: 20 (default)
- RDS instances: 20 (default)

**Solutions**:
1. **Request limit increase** in AWS console
2. **Use different region**
3. **Clean up unused resources**

### Subnet CIDR Conflicts
**Error**: CIDR block overlap

**Solution**: Use non-overlapping ranges
```hcl
# Avoid conflicts with existing VPCs
vpc_cidr = "10.1.0.0/16"  # Instead of 10.0.0.0/16
```

### RDS Creation Timeout
**Error**: RDS instance creation taking too long

**Causes**:
- First RDS instance in region (takes longer)
- Large instance class
- Multi-AZ configuration

**Solutions**:
1. **Wait longer** (up to 20 minutes is normal)
2. **Check RDS console** for detailed status
3. **Use smaller instance class** for testing

## Connectivity Issues

### SSH Connection Refused
**Error**: `Connection refused` when SSH to instances

**Debugging steps**:
1. **Check instance state**:
   ```bash
   ./status.sh
   ```

2. **Verify security groups**:
   ```bash
   aws ec2 describe-security-groups --group-names "pgbouncer-ec2-*"
   ```

3. **Check SSH key permissions**:
   ```bash
   chmod 600 terraform/pgbouncer-key.pem
   ```

4. **Test network connectivity**:
   ```bash
   telnet <instance-ip> 22
   ```

### IP Address Changed
**Error**: SSH works then stops working

**Cause**: Your public IP address changed

**Solution**:
1. **Get new IP**:
   ```bash
   curl https://ipinfo.io/ip
   ```

2. **Update terraform.tfvars**:
   ```hcl
   your_ip_address = "NEW.IP.ADDRESS/32"
   ```

3. **Re-apply**:
   ```bash
   cd terraform && terraform apply
   ```

### Database Connection Issues
**Error**: Cannot connect to RDS

**Debugging steps**:
1. **Check RDS status**:
   ```bash
   aws rds describe-db-instances --db-instance-identifier pgbouncer-test-db
   ```

2. **Verify security groups** allow PostgreSQL (port 5432)

3. **Test from PgBouncer server**:
   ```bash
   # SSH to PgBouncer server
   psql -h <rds-endpoint> -p 5432 -U postgres -d testdb
   ```

## PgBouncer Issues

### PgBouncer Not Starting
**Error**: PgBouncer service failed to start

**Debugging steps**:
1. **Check service status**:
   ```bash
   sudo systemctl status pgbouncer
   ```

2. **View logs**:
   ```bash
   sudo journalctl -u pgbouncer -f
   ```

3. **Check configuration**:
   ```bash
   sudo pgbouncer -d /etc/pgbouncer/pgbouncer.ini
   ```

4. **Test configuration manually**:
   ```bash
   sudo -u pgbouncer pgbouncer -v /etc/pgbouncer/pgbouncer.ini
   ```

### Authentication Failures
**Error**: `FATAL: password authentication failed`

**Causes**:
- Wrong password in userlist.txt
- MD5 hash mismatch
- User doesn't exist in PostgreSQL

**Solutions**:
1. **Check userlist.txt**:
   ```bash
   sudo cat /etc/pgbouncer/userlist.txt
   ```

2. **Regenerate password hash**:
   ```bash
   echo -n "passwordusername" | md5sum
   # Add "md5" prefix to result
   ```

3. **Test direct DB connection**:
   ```bash
   psql -h <rds-endpoint> -U postgres -d testdb
   ```

### Connection Pool Issues
**Error**: Pool queue full or timeouts

**Solutions**:
1. **Check pool status**:
   ```bash
   psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW POOLS;"
   ```

2. **Increase pool size** in `/etc/pgbouncer/pgbouncer.ini`:
   ```ini
   default_pool_size = 150
   max_db_connections = 150
   ```

3. **Restart PgBouncer**:
   ```bash
   sudo systemctl restart pgbouncer
   ```

## Performance Test Issues

### pgbench Command Not Found
**Error**: `pgbench: command not found`

**Solution**: Install PostgreSQL client tools
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql-client postgresql-contrib

# CentOS/RHEL
sudo yum install postgresql postgresql-contrib
```

### Test Data Missing
**Error**: `relation "pgbench_accounts" does not exist`

**Solution**: Initialize test data
```bash
# Connect to database and create tables
psql -h <db-host> -U postgres -d testdb

# In psql:
\i /path/to/pgbench-schema.sql
```

**Or recreate automatically**:
```bash
# Re-run PgBouncer setup script
sudo /var/lib/cloud/instances/*/user-data.txt
```

### High Latency Results
**Cause**: Network or instance performance issues

**Debugging**:
1. **Check network latency**:
   ```bash
   ping <database-host>
   ```

2. **Monitor system resources**:
   ```bash
   htop
   iostat 1
   ```

3. **Check database performance**:
   ```sql
   SELECT * FROM pg_stat_activity;
   ```

4. **Use larger instances** for more consistent results

### Tests Hanging or Timing Out
**Causes**:
- Connection limits reached
- Database overloaded
- Network issues

**Solutions**:
1. **Reduce concurrent connections**:
   ```bash
   pgbench -c 10 -j 5 -t 50  # Instead of higher values
   ```

2. **Check connection limits**:
   ```sql
   SHOW max_connections;
   SELECT count(*) FROM pg_stat_activity;
   ```

3. **Monitor system load**:
   ```bash
   uptime
   free -m
   ```

## AWS-Specific Issues

### Service Quotas/Limits
**Error**: Resource quota exceeded

**Check current limits**:
```bash
aws service-quotas list-service-quotas --service-code ec2
aws service-quotas list-service-quotas --service-code rds
```

**Request increases**:
- Use AWS console → Service Quotas
- Or AWS support case

### Region Availability
**Error**: Service not available in region

**Solutions**:
1. **Choose different region**:
   ```hcl
   aws_region = "us-east-1"  # Or other region
   ```

2. **Check service availability**:
   ```bash
   aws ec2 describe-regions
   aws rds describe-orderable-db-instance-options --engine postgres
   ```

### Cost Alerts
**Issue**: Unexpected charges

**Prevention**:
1. **Set up billing alerts** in AWS console
2. **Monitor costs**:
   ```bash
   aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-02 --granularity DAILY --metrics BlendedCost
   ```
3. **Clean up regularly**:
   ```bash
   ./cleanup.sh
   ```

## General Debugging

### Log Collection
**Collect logs for troubleshooting**:

1. **Cloud-init logs**:
   ```bash
   sudo cat /var/log/cloud-init-output.log
   sudo cat /var/log/cloud-init.log
   ```

2. **System logs**:
   ```bash
   sudo journalctl -xe
   sudo journalctl -u pgbouncer -n 50
   ```

3. **Application logs**:
   ```bash
   sudo cat /var/log/pgbouncer/pgbouncer.log
   ```

### Network Debugging
```bash
# Test connectivity
telnet <host> <port>
nc -zv <host> <port>

# DNS resolution
nslookup <hostname>
dig <hostname>

# Routing
traceroute <host>
```

### Resource Monitoring
```bash
# CPU and memory
htop
free -h

# Disk usage
df -h

# Network
netstat -tulpn
ss -tulpn
```

### Emergency Cleanup
**If deployment fails and resources are stuck**:

1. **Force destroy**:
   ```bash
   cd terraform
   terraform destroy -auto-approve
   ```

2. **Manual cleanup in AWS console**:
   - Terminate EC2 instances
   - Delete RDS instances
   - Delete VPCs
   - Remove security groups

3. **Clean Terraform state**:
   ```bash
   rm terraform.tfstate*
   rm -rf .terraform/
   ```

## Getting Help

### Information to Collect
When seeking help, provide:

1. **Error messages** (exact text)
2. **System information**:
   ```bash
   terraform version
   aws --version
   uname -a
   ```
3. **Configuration files** (redact sensitive data)
4. **Log files** (relevant sections)

### Resources
- **AWS Documentation**: https://docs.aws.amazon.com/
- **Terraform Documentation**: https://www.terraform.io/docs/
- **PgBouncer Documentation**: https://www.pgbouncer.org/
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/

### Support Channels
- AWS Support (if you have a support plan)
- Terraform Community Forums
- Stack Overflow (tag: terraform, aws, pgbouncer)
- GitHub Issues (for this project) 