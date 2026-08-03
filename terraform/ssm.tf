# 1. Security Group to allow the server to talk to the tunnels
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "Legacylens-SSM-Endpoints-SG"
  description = "Allow HTTPS from VPC to SSM Endpoints"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.legacylens.cidr_block]
  }
}

# 2. Tunnel 1: Core SSM Service
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

# 3. Tunnel 2: SSM Session Manager Messages (The browser terminal)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

# 4. Tunnel 3: EC2 Messages
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.legacylens.id
  service_name        = "com.amazonaws.ap-south-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}