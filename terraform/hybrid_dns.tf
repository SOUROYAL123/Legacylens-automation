resource "aws_subnet" "dns_outbound_1a" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.38.100.0/28"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "dns-outbound-1a"
  }
}

resource "aws_subnet" "dns_outbound_1b" {
  vpc_id            = aws_vpc.legacylens.id
  cidr_block        = "10.38.100.16/28"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "dns-outbound-1b"
  }
}

resource "aws_security_group" "dns_inbound_sg" {
  name        = "dns_inbound_sg"
  description = "Security group for inbound DNS"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "dns_outbound_sg" {
  name        = "dns_outbound_sg"
  description = "Security group for outbound DNS"
  vpc_id      = aws_vpc.legacylens.id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}