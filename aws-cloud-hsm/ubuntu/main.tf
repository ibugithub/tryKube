provider "aws" {
  region = "us-east-2"
}

# Use your public SSH key
resource "aws_key_pair" "ssh_key" {
  key_name   = "cloudhsm-key"
  public_key = file("${path.module}/cloudhsm-key.pub")
}

# Call the network module
module "network" {
  source         = "../modules/network"
  vpc_cidr       = "10.0.0.0/16"
  vpc_name       = "hsm-vpc"
  private_a_cidr = "10.0.1.0/24"
  private_b_cidr = "10.0.2.0/24"
  az_a           = "us-east-2a"
  az_b           = "us-east-2b"
}

# Create EC2 instance
resource "aws_instance" "cloudhsm_host" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t3.small"
  key_name                    = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids      = [module.network.ssh_sg_id]
  associate_public_ip_address = true
  subnet_id                   = module.network.private_a_id

  tags = {
    Name = "cloudhsm-ubuntu-22"
  }
}