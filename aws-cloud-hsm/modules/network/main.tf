resource "aws_vpc" "hsm_vpc" {
  cidr_block = var.vpc_cidr
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
