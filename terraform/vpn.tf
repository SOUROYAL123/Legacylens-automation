# 1. Customer Gateway (On-Prem / Remote Corporate Router)
resource "aws_customer_gateway" "onprem_cgw" {
  bgp_asn    = 65000
  ip_address = "203.0.113.12" # On-prem public IP
  type       = "ipsec.1"

  tags = { Name = "legacylens-onprem-cgw" }
}

# 2. Central Transit Gateway (The Enterprise Hub)
resource "aws_ec2_transit_gateway" "main_tgw" {
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  vpn_ecmp_support                = "enable" # Enables bandwidth aggregation across multiple tunnels

  tags = { Name = "legacylens-production-tgw" }
}

# 3. AWS Site-to-Site IPsec VPN Connection (Terminating on the TGW)
resource "aws_vpn_connection" "hybrid_vpn" {
  transit_gateway_id  = aws_ec2_transit_gateway.main_tgw.id
  customer_gateway_id = aws_customer_gateway.onprem_cgw.id
  type                = "ipsec.1"
  static_routes_only  = false # Enables dynamic BGP routing

  tags = { Name = "legacylens-hybrid-tgw-vpn" }
}

# 4. Attach the Production VPC to the Transit Gateway Hub
resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_attachment" {
  # Updated with your verified subnet resource names
  subnet_ids         = [aws_subnet.private_app.id, aws_subnet.private_db_subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.main_tgw.id
  vpc_id             = aws_vpc.legacylens.id

  tags = { Name = "legacylens-tgw-vpc-attachment" }
}

# 5. Route VPC Traffic to the On-Premises Network via the TGW
resource "aws_route" "private_to_onprem" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "172.16.0.0/16" # Your on-premises network CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.main_tgw.id

  # Ensure the attachment is fully created before injecting the route
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc_attachment]
}