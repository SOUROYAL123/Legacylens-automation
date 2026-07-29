# 1. Provision Central Transit Gateway
resource "aws_ec2_transit_gateway" "central_tgw" {
  description                     = "Central Transit Gateway for LegacyLens Infrastructure"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  tags = { Name = "legacylens-central-tgw" }
}

# 2. Attach Production VPC to Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "prod_vpc_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.central_tgw.id
  vpc_id             = aws_vpc.legacylens.id 
  subnet_ids         = [aws_subnet.private_app.id, aws_subnet.private_db_subnet.id]
  tags = { Name = "legacylens-prod-tgw-attachment" }
}

# 3. Add Route to Private Subnet Route Table targeting Transit Gateway
resource "aws_route" "private_tgw_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.central_tgw.id
}