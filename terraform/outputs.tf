# Outputs for PgBouncer Performance Test Infrastructure

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.postgres.port
}

output "pgbouncer_public_ip" {
  description = "PgBouncer instance public IP"
  value       = aws_instance.pgbouncer.public_ip
}

output "pgbouncer_private_ip" {
  description = "PgBouncer instance private IP"
  value       = aws_instance.pgbouncer.private_ip
}

output "test_client_public_ip" {
  description = "Test client instance public IP"
  value       = aws_instance.test_client.public_ip
}

output "test_client_private_ip" {
  description = "Test client instance private IP"
  value       = aws_instance.test_client.private_ip
}

output "ssh_key_file" {
  description = "SSH private key file (if auto-generated)"
  value       = var.public_key == "" ? "${path.module}/pgbouncer-key.pem" : "Use your existing private key"
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    pgbouncer_server = "ssh -i ${var.public_key == "" ? "pgbouncer-key.pem" : "your-private-key.pem"} ubuntu@${aws_instance.pgbouncer.public_ip}"
    test_client     = "ssh -i ${var.public_key == "" ? "pgbouncer-key.pem" : "your-private-key.pem"} ubuntu@${aws_instance.test_client.public_ip}"
  }
}

output "connection_strings" {
  description = "Database connection strings"
  value = {
    direct_to_rds = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${var.db_name}"
    via_pgbouncer = "postgresql://${var.db_username}:${var.db_password}@${aws_instance.pgbouncer.private_ip}:6432/${var.db_name}"
  }
  sensitive = true
}

output "test_instructions" {
  description = "Instructions to run the performance tests"
  value = <<-EOT
    1. SSH into the test client:
       ${var.public_key == "" ? "chmod 600 pgbouncer-key.pem" : ""}
       ssh -i ${var.public_key == "" ? "pgbouncer-key.pem" : "your-private-key.pem"} ubuntu@${aws_instance.test_client.public_ip}

    2. Wait for setup to complete (check with: tail -f /var/log/cloud-init-output.log)

    3. Run the performance comparison:
       ./run_performance_test.sh

    4. View detailed results in the generated reports

    5. Don't forget to destroy resources when done:
       terraform destroy
  EOT
}

output "cost_estimate" {
  description = "Estimated monthly cost if resources are left running"
  value = <<-EOT
    Estimated AWS costs (if left running 24/7):
    - RDS db.t3.micro: ~$13/month
    - 2x EC2 t3.micro: ~$17/month
    - Total: ~$30/month
    
    Remember to run 'terraform destroy' after testing!
  EOT
} 