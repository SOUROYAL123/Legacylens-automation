# -----------------------------------------------------------------------------
# Main Producer VPC (aws_vpc.legacylens - 10.38.0.0/16)
# -----------------------------------------------------------------------------
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

# Public Subnet (Required for Bastion Host in main.tf)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.legacylens.id
  cidr_block              = "10.38.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "legacylens-public-subnet"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.legacylens.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "legacylens-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Private Subnets
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.38.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "legacylens-private-app"
  }
}

resource "aws_subnet" "private_db_subnet" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.38.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "legacylens-private-db-1"
  }
}

resource "aws_subnet" "private_db_subnet_2" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.38.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "legacylens-private-db-2"
  }
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.legacylens.id

  tags = {
    Name = "legacylens-private-rt"
  }
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_db_assoc" {
  subnet_id      = aws_subnet.private_db_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_db_2_assoc" {
  subnet_id      = aws_subnet.private_db_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# -----------------------------------------------------------------------------
# Consumer VPC (aws_vpc.alpha - 10.37.0.0/16)
# -----------------------------------------------------------------------------
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