# Variables for PgBouncer Performance Test Infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "availability_zone" {
  description = "Primary availability zone for resources"
  type        = string
  default     = "us-west-2a"
}

variable "availability_zone_secondary" {
  description = "Secondary availability zone for RDS subnet group"
  type        = string
  default     = "us-west-2b"
}

variable "your_ip_address" {
  description = "Your IP address in CIDR format (e.g., 1.2.3.4/32) for SSH access. Get it from https://whatismyipaddress.com/"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.your_ip_address))
    error_message = "IP address must be in CIDR format (e.g., 1.2.3.4/32)."
  }
}

variable "public_key" {
  description = "Public key for SSH access (leave empty to auto-generate)"
  type        = string
  default     = ""
}

# Database Configuration
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "testdb"
}

variable "db_username" {
  description = "PostgreSQL database username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type for PgBouncer and test client"
  type        = string
  default     = "t3.micro"
} 