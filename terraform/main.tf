# ====================================================================
# COMPUTE, DATABASE & SECURITY LAYER (main.tf)
# ====================================================================

provider "aws" {
  region = "ap-south-1" # Mumbai region
}

# 7. Security Firewall for Public Guard (Bastion Host)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH access to Bastion host"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bastion-sg" }
}

# 7b. Inner Firewall for Private App Server (Security Group Nesting)
resource "aws_security_group" "private_app_sg" {
  name        = "private-app-sg"
  description = "Access rules for hidden application server tier"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description     = "Allow SSH strictly from instances wearing Bastion SG badge"
    from_port       = 22
    to_port         = 22
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

# 14. Task 1 Compliance: Database Security Group (Least Privilege Referencing)
resource "aws_security_group" "db_sg" {
  name        = "Legacylens-DB-SG"
  description = "Access rules for PostgreSQL database instances"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description     = "Allow PostgreSQL port 5432 strictly from Private App SG badge"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_app_sg.id]
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

# 8. Hardened EC2 Bastion Host Instance
resource "aws_instance" "bastion" {
  ami                    = "ami-0522ab6e1ddcc7055"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = "legacylens-key"
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  tags                   = { Name = "Legacylens-Bastion-Host" }
}

# 16. Private Application Server (WITH SSM PROFILE ATTACHED)
resource "aws_instance" "private_app_server" {
  ami                    = "ami-0522ab6e1ddcc7055"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]
  key_name               = "legacylens-key"
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  tags                   = { Name = "Legacylens-Private-App-Server" }
}

# 13. Managed Multi-AZ Database Group Mapping
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "legacylens-db-subnet-group"
  subnet_ids = [aws_subnet.private_db_subnet.id, aws_subnet.private_db_subnet_2.id]
  tags       = { Name = "Legacylens-DB-Subnet-Group" }
}

# 15. Production-Ready Managed Postgres Database Engine (Multi-AZ)
resource "aws_db_instance" "postgres_db" {
  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  db_name                = "legacylens_prod"
  username               = "db_admin_user"
  password               = "LegacyLensSecure2026!"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az               = true
  skip_final_snapshot    = true
  tags                   = { Name = "Legacylens-Production-Database" }
}

# 17. IAM Role for Systems Manager (SSM)
resource "aws_iam_role" "ssm_role" {
  name = "Legacylens-SSM-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# 18. Attach the AmazonSSMManagedInstanceCore Policy to the Role
resource "aws_iam_role_policy_attachment" "ssm_policy_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 19. Create an Instance Profile to pass the IAM Role to the Bastion Instance
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "Legacylens-SSM-Profile"
  role = aws_iam_role.ssm_role.name
}