# ====================================================================
# COMPUTE, DATABASE, SECURITY & OUTPUTS (main.tf)
# ====================================================================

provider "aws" {
  region = "ap-south-1" # Mumbai region
}

# Dynamic AMI Data Lookup (Prevents Invalid AMI ID Errors)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

# 1. SSM Bastion Security Group (Zero Inbound Ports)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH access to Bastion host"
  vpc_id      = aws_vpc.legacylens.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bastion-sg" }
}

# 2. Inner Firewall for Private App Server
resource "aws_security_group" "private_app_sg" {
  name        = "private-app-sg"
  description = "Access rules for hidden application server tier"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description     = "Allow app access from Bastion"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    description = "Allow all outbound traffic via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "Legacylens-Private-App-SG" }
}

# 3. Database Security Group
resource "aws_security_group" "db_sg" {
  name        = "Legacylens-DB-SG"
  description = "Access rules for PostgreSQL database instances"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "Allow PostgreSQL port 5432 from App Server and Bastion"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.private_app_sg.id,
      aws_security_group.bastion_sg.id
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "Legacylens-DB-SG" }
}

# 4. Hardened SSM Bastion Host Instance
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_app_az1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted = true
  }
  tags = { Name = "Legacylens-Bastion-Host" }
}

# 5. Private Application Server
resource "aws_instance" "private_app_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_app_az1.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted = true
  }
  tags = { Name = "Legacylens-Private-App-Server" }
}

# 6. DB Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "legacylens-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_az1.id, aws_subnet.private_db_az2.id]
  tags       = { Name = "Legacylens-DB-Subnet-Group" }
}

# 7. Production Postgres Database Instance
resource "aws_db_instance" "postgres_db" {
  allocated_storage                    = 20
  max_allocated_storage                = 100
  engine                               = "postgres"
  engine_version                       = "16"
  instance_class                       = "db.t4g.micro"
  db_name                              = "legacylens_prod"
  username                             = "db_admin_user"
  password                             = "LegacyLensSecure2026!"
  db_subnet_group_name                 = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids               = [aws_security_group.db_sg.id]
  multi_az                             = false 
  skip_final_snapshot                  = true
  storage_encrypted                    = true
  backup_retention_period              = 1
  performance_insights_enabled         = true
  deletion_protection                  = false
  iam_database_authentication_enabled  = true

  tags = { Name = "Legacylens-Production-Database" }
}

# 8. IAM Role for Systems Manager (SSM)
resource "aws_iam_role" "ssm_role" {
  name = "Legacylens-SSM-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# 9. Attach SSM Policy
resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 10. Instance Profile for SSM
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "Legacylens-SSM-Profile"
  role = aws_iam_role.ssm_role.name
}

# ====================================================================
# PRIVATE LINK & SSM VPC ENDPOINTS (Fixes Offline SSM Agent Error)
# ====================================================================

# 11. Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints_sg" {
  name_prefix = "ssm-vpc-endpoints-" # Changed to prefix to avoid name collisions
  description = "Allow private subnets to reach AWS SSM"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "Allow HTTPS from VPC private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.legacylens.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = { Name = "Legacylens-VPC-Endpoints-SG" }

  # Tells Terraform to build the new one and attach it BEFORE deleting the old one
  lifecycle {
    create_before_destroy = true
  }
}

# 12. SSM Core Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_az1.id, aws_subnet.private_app_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
  tags = { Name = "Legacylens-SSM-Endpoint" }
}

# 13. SSMMessages Endpoint (Interactive Terminal Sessions)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_az1.id, aws_subnet.private_app_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
  tags = { Name = "Legacylens-SSMMessages-Endpoint" }
}

# 14. EC2Messages Endpoint (Agent Status & Telemetry)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_az1.id, aws_subnet.private_app_az2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
  tags = { Name = "Legacylens-EC2Messages-Endpoint" }
}

# ====================================================================
# OUTPUTS
# ====================================================================

output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "The Instance ID of the SSM Bastion host for port forwarding"
}

output "private_app_server_id" {
  value       = aws_instance.private_app_server.id
  description = "The Instance ID of the Private Application Server"
}

output "postgres_endpoint" {
  value       = aws_db_instance.postgres_db.address
  description = "The internal RDS endpoint URL"
}