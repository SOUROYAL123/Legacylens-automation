# 1. Target Group inside Producer VPC (aws_vpc.legacylens)
resource "aws_vpclattice_target_group" "order_service" {
  name = "order-service-tg"
  type = "IP"

  config {
    port             = 443
    protocol         = "HTTPS"
    vpc_identifier   = aws_vpc.legacylens.id
    protocol_version = "HTTP1"

    health_check {
      enabled  = true
      path     = "/health"
      protocol = "HTTPS"

      matcher {
        value = "200"
      }
    }
  }
}

# 2. VPC Lattice Service & Custom Domain
resource "aws_vpclattice_service" "order_service" {
  name               = "order-service"
  custom_domain_name = "order-service.legacylens.internal"
  auth_type          = "AWS_IAM"
}

# 3. HTTPS Listener (Port 443) forwarding to Target Group
resource "aws_vpclattice_listener" "order_service_https" {
  name               = "https-listener"
  service_identifier = aws_vpclattice_service.order_service.id
  protocol           = "HTTPS"
  port               = 443

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order_service.id
        weight                  = 100
      }
    }
  }
}

# 4. Managed Layer-7 Service Network
resource "aws_vpclattice_service_network" "legacylens_network" {
  name      = "legacylens-service-network"
  auth_type = "AWS_IAM"
}

# 5. Associate Producer VPC (aws_vpc.legacylens) with Service Network
resource "aws_vpclattice_service_network_vpc_association" "producer_assoc" {
  service_network_identifier = aws_vpclattice_service_network.legacylens_network.id
  vpc_identifier             = aws_vpc.legacylens.id
}

# 6. Associate Consumer VPC (aws_vpc.alpha) with Service Network
resource "aws_vpclattice_service_network_vpc_association" "consumer_assoc" {
  service_network_identifier = aws_vpclattice_service_network.legacylens_network.id
  vpc_identifier             = aws_vpc.alpha.id
}

# 7. Associate Order Service to Service Network
resource "aws_vpclattice_service_network_service_association" "service_assoc" {
  service_identifier         = aws_vpclattice_service.order_service.id
  service_network_identifier = aws_vpclattice_service_network.legacylens_network.id
}

# 8. Zero-Trust IAM Auth Policy (Fixed to use .arn)
resource "aws_vpclattice_auth_policy" "network_auth_policy" {
  resource_identifier = aws_vpclattice_service_network.legacylens_network.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "vpc-lattice-svcs:Invoke"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = var.aws_organization_id
          }
        }
      }
    ]
  })
}