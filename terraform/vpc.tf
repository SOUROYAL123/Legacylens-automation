# ====================================================================
# PRODUCER VPC (aws_vpc.legacylens - 10.38.0.0/16)
# ====================================================================

resource "aws_vpc" "legacylens" {
  cidr_block           = var.vpc_beta_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "VPC-LegacyLens-Producer"
  }
}

# Internet Gateway for Public Access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.legacylens.id

  tags = {
    Name = "legacylens-igw"
  }
}

# -----------------------------------------------------------------------------
# AVAILABILITY ZONE 1 (ap-south-1a)
# -----------------------------------------------------------------------------

resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "legacylens-public-az1" }
}

resource "aws_subnet" "private_app_az1" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.10.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = { Name = "legacylens-private-app-az1" }
}

resource "aws_subnet" "private_db_az1" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.20.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false # Strictly enforced isolation

  tags = { Name = "legacylens-private-db-az1" }
}

# NAT Gateway AZ1
resource "aws_eip" "nat_az1" {
  domain = "vpc"
  tags   = { Name = "legacylens-eip-az1" }
}

resource "aws_nat_gateway" "nat_az1" {
  allocation_id = aws_eip.nat_az1.id
  subnet_id     = aws_subnet.public_az1.id
  tags          = { Name = "legacylens-nat-az1" }
}

# -----------------------------------------------------------------------------
# AVAILABILITY ZONE 2 (ap-south-1b)
# -----------------------------------------------------------------------------

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.1.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = { Name = "legacylens-public-az2" }
}

resource "aws_subnet" "private_app_az2" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.11.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = { Name = "legacylens-private-app-az2" }
}

resource "aws_subnet" "private_db_az2" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.21.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false # Strictly enforced isolation

  tags = { Name = "legacylens-private-db-az2" }
}

# NAT Gateway AZ2
resource "aws_eip" "nat_az2" {
  domain = "vpc"
  tags   = { Name = "legacylens-eip-az2" }
}

resource "aws_nat_gateway" "nat_az2" {
  allocation_id = aws_eip.nat_az2.id
  subnet_id     = aws_subnet.public_az2.id
  tags          = { Name = "legacylens-nat-az2" }
}

# -----------------------------------------------------------------------------
# ROUTING TABLES & ASSOCIATIONS (PRODUCER VPC)
# -----------------------------------------------------------------------------

# 1. Public Route Table (IGW)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "legacylens-public-rt" }
}

resource "aws_route_table_association" "pub_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public_rt.id
}

# 2. Private App Route Table AZ1 (Points to NAT AZ1)
resource "aws_route_table" "private_rt_az1" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_az1.id
  }

  tags = { Name = "legacylens-private-rt-az1" }
}

resource "aws_route_table_association" "priv_app_az1" {
  subnet_id      = aws_subnet.private_app_az1.id
  route_table_id = aws_route_table.private_rt_az1.id
}

# 3. Private App Route Table AZ2 (Points to NAT AZ2)
resource "aws_route_table" "private_rt_az2" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_az2.id
  }

  tags = { Name = "legacylens-private-rt-az2" }
}

resource "aws_route_table_association" "priv_app_az2" {
  subnet_id      = aws_subnet.private_app_az2.id
  route_table_id = aws_route_table.private_rt_az2.id
}

# 4. Database Route Table (NO INTERNET ROUTE)
resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.legacylens.id

  tags = { Name = "legacylens-db-rt" }
}

resource "aws_route_table_association" "db_az1" {
  subnet_id      = aws_subnet.private_db_az1.id
  route_table_id = aws_route_table.db_rt.id
}

resource "aws_route_table_association" "db_az2" {
  subnet_id      = aws_subnet.private_db_az2.id
  route_table_id = aws_route_table.db_rt.id
}


# ====================================================================
# CONSUMER VPC (aws_vpc.alpha - 10.37.0.0/16)
# ====================================================================

resource "aws_vpc" "alpha" {
  cidr_block           = var.vpc_alpha_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "VPC-Alpha-Consumer"
  }
}

resource "aws_subnet" "alpha_private_a" {
  vpc_id            = aws_vpc.alpha.id
  cidr_block        = "10.37.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "alpha-private-a"
  }
}

resource "aws_subnet" "alpha_private_b" {
  vpc_id            = aws_vpc.alpha.id
  cidr_block        = "10.37.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "alpha-private-b"
  }
}

# Consumer VPC Private Route Table
resource "aws_route_table" "alpha_private_rt" {
  vpc_id = aws_vpc.alpha.id

  tags = {
    Name = "alpha-private-rt"
  }
}

resource "aws_route_table_association" "alpha_priv_a" {
  subnet_id      = aws_subnet.alpha_private_a.id
  route_table_id = aws_route_table.alpha_private_rt.id
}

resource "aws_route_table_association" "alpha_priv_b" {
  subnet_id      = aws_subnet.alpha_private_b.id
  route_table_id = aws_route_table.alpha_private_rt.id
}