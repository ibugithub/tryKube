provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "hsm_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = var.vpc_name }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.hsm_vpc.id
  cidr_block        = var.private_a_cidr
  availability_zone = var.az_a
  tags = { Name = "private-subnet-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.hsm_vpc.id
  cidr_block        = var.private_b_cidr
  availability_zone = var.az_b
  tags = { Name = "private-subnet-b" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.hsm_vpc.id
  cidr_block              = var.public_a_cidr
  availability_zone       = var.az_a
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.hsm_vpc.id
  name   = "hsm-allow-ssh"

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.hsm_vpc.id

  tags = {
    Name = "hsm-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hsm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "hsm-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
