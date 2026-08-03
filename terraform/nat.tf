# 1. Allocate a Static Public IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  
  tags = { Name = "legacylens-nat-eip" }
}

# 2. Create the NAT Gateway in the Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id # Assumes this exists based on your bastion host config

  tags = { Name = "Legacylens-NAT-GW" }
}

# 3. Route outbound internet traffic from the Private Route Table to the NAT Gateway
resource "aws_route" "private_internet_access" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}