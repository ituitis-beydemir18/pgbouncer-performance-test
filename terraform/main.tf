# PgBouncer Performance Test Infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Key pair for SSH access
resource "aws_key_pair" "pgbouncer_key" {
  key_name   = "pgbouncer-test-key"
  public_key = var.public_key != "" ? var.public_key : tls_private_key.pgbouncer_key[0].public_key_openssh

  tags = {
    Name        = "PgBouncer Test Key"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Generate key pair if not provided
resource "tls_private_key" "pgbouncer_key" {
  count     = var.public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key locally if generated
resource "local_file" "private_key" {
  count           = var.public_key == "" ? 1 : 0
  content         = tls_private_key.pgbouncer_key[0].private_key_pem
  filename        = "${path.module}/pgbouncer-key.pem"
  file_permission = "0600"
}

# VPC
resource "aws_vpc" "pgbouncer_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "pgbouncer-vpc"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "pgbouncer_igw" {
  vpc_id = aws_vpc.pgbouncer_vpc.id

  tags = {
    Name        = "pgbouncer-igw"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.pgbouncer_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "pgbouncer-public-subnet"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Private Subnet for RDS
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.pgbouncer_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zone

  tags = {
    Name        = "pgbouncer-private-subnet-1"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Second private subnet for RDS (required for subnet group)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.pgbouncer_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = var.availability_zone_secondary

  tags = {
    Name        = "pgbouncer-private-subnet-2"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.pgbouncer_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pgbouncer_igw.id
  }

  tags = {
    Name        = "pgbouncer-public-rt"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name_prefix = "pgbouncer-ec2-"
  vpc_id      = aws_vpc.pgbouncer_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_address]
  }

  ingress {
    description = "PgBouncer"
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "pgbouncer-ec2-sg"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name_prefix = "pgbouncer-rds-"
  vpc_id      = aws_vpc.pgbouncer_vpc.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  tags = {
    Name        = "pgbouncer-rds-sg"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "pgbouncer_db_subnet_group" {
  name       = "pgbouncer-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name        = "pgbouncer-db-subnet-group"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres" {
  identifier = "pgbouncer-test-db"

  # Database Configuration
  engine              = "postgres"
  engine_version      = "15"
  instance_class      = var.db_instance_class
  allocated_storage   = 20
  max_allocated_storage = 100
  storage_type        = "gp2"
  storage_encrypted   = false

  # Database Settings
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network Configuration
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.pgbouncer_db_subnet_group.name
  publicly_accessible    = false

  # Backup and Maintenance
  backup_retention_period = 0
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  skip_final_snapshot    = true
  deletion_protection    = false

  # Performance Configuration
  parameter_group_name = aws_db_parameter_group.postgres_params.name

  tags = {
    Name        = "pgbouncer-test-db"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# DB Parameter Group to set max_connections
resource "aws_db_parameter_group" "postgres_params" {
  family = "postgres15"
  name   = "pgbouncer-test-params"

  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/32768}"
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "pgbouncer-test-params"
    Environment = "test"
    Project     = "pgbouncer-performance"
  }
}

# PgBouncer EC2 Instance
resource "aws_instance" "pgbouncer" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.pgbouncer_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public_subnet.id

  user_data = base64encode(templatefile("${path.module}/user-data/pgbouncer-setup.sh", {
    db_host     = aws_db_instance.postgres.address
    db_port     = aws_db_instance.postgres.port
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
  }))

  tags = {
    Name        = "pgbouncer-server"
    Environment = "test"
    Project     = "pgbouncer-performance"
    Role        = "pgbouncer"
  }

  depends_on = [aws_db_instance.postgres]
}

# Test Client EC2 Instance
resource "aws_instance" "test_client" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.pgbouncer_key.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public_subnet.id

  user_data = base64encode(templatefile("${path.module}/user-data/client-setup.sh", {
    db_host        = aws_db_instance.postgres.address
    db_port        = aws_db_instance.postgres.port
    db_name        = var.db_name
    db_username    = var.db_username
    db_password    = var.db_password
    pgbouncer_host = aws_instance.pgbouncer.private_ip
    pgbouncer_port = 6432
  }))

  tags = {
    Name        = "pgbouncer-test-client"
    Environment = "test"
    Project     = "pgbouncer-performance"
    Role        = "test-client"
  }

  depends_on = [aws_db_instance.postgres, aws_instance.pgbouncer]
} 