# ====================================================================
# NETWORK LAYER (vpc.tf)
# ====================================================================

# 1. Core Virtual Private Cloud Perimeter (Production)
resource "aws_vpc" "legacylens" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "Legacylens-VPC" }
}

# 2. Public Facing Lobby Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "Legacylens-Public-Subnet" }
}

# 3. Inbound/Outbound Public Highway Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.legacylens.id
  tags   = { Name = "Legacylens-IGW" }
}

# 4. Main Route Table Configuration (Public Network Rules -> IGW)
resource "aws_default_route_table" "public_rt" {
  default_route_table_id = aws_vpc.legacylens.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Legacylens-Public-RT" }
}

# 5. Isolated Application Core Subnet
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
  tags              = { Name = "Legacylens-Private-App" }
}

# 6. Isolated Database Subnets (Multi-AZ)
resource "aws_subnet" "private_db_subnet" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"
  tags              = { Name = "Legacylens-Private-DB-Subnet" }
}

resource "aws_subnet" "private_db_subnet_2" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-south-1a"
  tags              = { Name = "Legacylens-Private-DB-Subnet2" }
}

# 7 & 8. Static Public IP and NAT Gateway
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "Legacylens-NAT-EIP" }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags          = { Name = "Legacylens-NAT-GW" }
}

# 9 & 10. Private Route Table & Association
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.legacylens.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "Legacylens-Private-RT" }
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private.id
}

# ====================================================================
# MULTI-VPC STAGING & PEERING ARCHITECTURE
# ====================================================================

# 11. Secondary Staging Virtual Private Cloud
resource "aws_vpc" "staging_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "legacylens-staging-vpc" }
}

# 12. VPC Peering Connection Request (Production <-> Staging)
resource "aws_vpc_peering_connection" "prod_to_staging" {
  peer_vpc_id = aws_vpc.staging_vpc.id
  vpc_id      = aws_vpc.legacylens.id
  auto_accept = true

  tags = { Name = "prod-to-staging-peering" }
}

# 13. Route Table Entry for Prod Private Subnet -> Staging CIDR
resource "aws_route" "prod_to_staging_route" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = "10.1.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.prod_to_staging.id
}

# ====================================================================
# ON-PREMISES TO AWS HYBRID CLOUD VPN
# ====================================================================

# 14. On-Premises Customer Gateway (The Simulated Corporate Router)
resource "aws_customer_gateway" "onprem_cgw" {
  bgp_asn    = 65000
  ip_address = "203.0.113.12" # Dummy Public IP of on-prem router
  type       = "ipsec.1"

  tags = { Name = "legacylens-onprem-cgw" }
}

# 15. Virtual Private Gateway (The AWS-Side VPN Receiver)
resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id = aws_vpc.legacylens.id

  tags = { Name = "legacylens-vpg" }
}

# 16. IPSec Site-to-Site VPN Connection (The Encrypted Tunnel)
resource "aws_vpn_connection" "site_to_site" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id = aws_customer_gateway.onprem_cgw.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = { Name = "legacylens-s2s-vpn" }
}