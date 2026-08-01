# ====================================================================
# HYBRID DNS ARCHITECTURE (hybrid_dns.tf)
# ====================================================================

# 1. Dedicated /28 Subnets for Outbound DNS
resource "aws_subnet" "dns_outbound_1a" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.100.0/28"
  availability_zone = "ap-south-1a"
  tags              = { Name = "Legacylens-DNS-Outbound-1a" }
}

resource "aws_subnet" "dns_outbound_1b" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.100.16/28"
  availability_zone = "ap-south-1b"
  tags              = { Name = "Legacylens-DNS-Outbound-1b" }
}

# 2. Security Group for INBOUND DNS (From On-Prem to AWS)
resource "aws_security_group" "dns_inbound_sg" {
  name        = "Legacylens-DNS-Inbound"
  description = "Allow DNS queries from on-premises"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    description = "DNS TCP from On-Prem"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"]
  }
  ingress {
    description = "DNS UDP from On-Prem"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["172.16.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Security Group for OUTBOUND DNS (From AWS to On-Prem)
resource "aws_security_group" "dns_outbound_sg" {
  name        = "Legacylens-DNS-Outbound"
  description = "Allow DNS queries to on-premises"
  vpc_id      = aws_vpc.legacylens.id

  egress {
    description = "DNS TCP to On-Prem"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["172.16.1.53/32"]
  }
  egress {
    description = "DNS UDP to On-Prem"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["172.16.1.53/32"]
  }
}

# 4. Route 53 Inbound Endpoint (The Incoming Receptionist)
resource "aws_route53_resolver_endpoint" "inbound" {
  name      = "legacylens-inbound-endpoint"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.dns_inbound_sg.id]

  ip_address { subnet_id = aws_subnet.private_app.id }
  ip_address { subnet_id = aws_subnet.private_db_subnet.id }
}

# 5. Route 53 Outbound Endpoint (The Outgoing Receptionist)
resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "legacylens-outbound-endpoint"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_outbound_sg.id]

  ip_address { subnet_id = aws_subnet.dns_outbound_1a.id }
  ip_address { subnet_id = aws_subnet.dns_outbound_1b.id }
}

# 6. Forwarding Rule: Send 'onprem.local' to 172.16.1.53
resource "aws_route53_resolver_rule" "forward_to_onprem" {
  domain_name          = "onprem.local"
  name                 = "forward-to-legacy-warehouse"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip = "172.16.1.53"
  }
}

# 7. Associate the rule with the Hub VPC
resource "aws_route53_resolver_rule_association" "hub_vpc_assoc" {
  resolver_rule_id = aws_route53_resolver_rule.forward_to_onprem.id
  vpc_id           = aws_vpc.legacylens.id
}

# 8. Share the Resolver Rule via AWS RAM so Spoke VPCs can use it
resource "aws_ram_resource_share" "dns_rule_share" {
  name                      = "legacylens-dns-rule-share"
  allow_external_principals = true
}

resource "aws_ram_resource_association" "dns_rule_assoc" {
  resource_arn       = aws_route53_resolver_rule.forward_to_onprem.arn
  resource_share_arn = aws_ram_resource_share.dns_rule_share.arn
}