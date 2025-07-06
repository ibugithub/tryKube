provider "aws" {
  region = "us-east-2"
}

# Use your public SSH key
resource "aws_key_pair" "ssh_key" {
  key_name   = "cloudhsm-key"
  public_key = file("${path.module}/cloudhsm-key.pub")
}

# Use default VPC
resource "aws_vpc" "hsm_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "hsm-vpc"
  }
}

# 2. Subnet A
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.hsm_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-a"
  }
}

# 3. Subnet B
resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.hsm_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-b"
  }
}

# Allow SSH from anywhere
resource "aws_security_group" "allow_ssh" {
  name        = "hsm-allow-ssh"
  vpc_id      = aws_vpc.hsm_vpc.id

  ingress {
    description = "Allow SSH"
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

# Create EC2 instance
resource "aws_instance" "cloudhsm_host" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t3.small"
  key_name                    = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.private_a.id  

  tags = {
    Name = "cloudhsm-ubuntu-22"
  }
}

#CloudHSM Cluster
resource "aws_cloudhsm_v2_cluster" "hsm_cluster" {
  hsm_type   = "hsm1.medium"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "hsm-cluster"
  }
}

#HSM appliance
resource "aws_cloudhsm_v2_hsm" "hsm_instance" {
  cluster_id        = aws_cloudhsm_v2_cluster.hsm_cluster.cluster_id
  availability_zone = "us-east-2a"
}

# Output public IP
output "ec2_public_ip" {
  value = aws_instance.cloudhsm_host.public_ip
}
