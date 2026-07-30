# 1. Customer Gateway (On-Prem / Remote Router)
resource "aws_customer_gateway" "onprem_cgw" {
  bgp_asn    = 65000
  ip_address = "203.0.113.12" # On-prem public IP
  type       = "ipsec.1"

  tags = { Name = "legacylens-onprem-cgw" }
}

# 2. Virtual Private Gateway attached to VPC
resource "aws_vpn_gateway" "vpc_vgw" {
  vpc_id = aws_vpc.legacylens.id  # <-- FIXED: Removed "_vpc"

  tags = { Name = "legacylens-vpc-vgw" }
}

# 3. AWS Site-to-Site IPsec VPN Connection
resource "aws_vpn_connection" "hybrid_vpn" {
  vpn_gateway_id      = aws_vpn_gateway.vpc_vgw.id
  customer_gateway_id = aws_customer_gateway.onprem_cgw.id
  type                = "ipsec.1"
  static_routes_only  = false # Enables dynamic BGP routing

  tags = { Name = "legacylens-hybrid-ipsec-vpn" }
}

# 4. Enable Automatic Route Propagation on Private Route Table
resource "aws_vpn_gateway_route_propagation" "private_vpn_propagate" {
  vpn_gateway_id = aws_vpn_gateway.vpc_vgw.id
  route_table_id = aws_route_table.private_route_table.id
}