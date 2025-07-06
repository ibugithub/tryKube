provider "aws" {
  region = "us-east-2"
}

module "network" {
  source         = "../modules/network"
  vpc_cidr       = "10.0.0.0/16"
  vpc_name       = "hsm-vpc"
  private_a_cidr = "10.0.1.0/24"
  private_b_cidr = "10.0.2.0/24"
  az_a           = "us-east-2a"
  az_b           = "us-east-2b"
}



#CloudHSM Cluster
resource "aws_cloudhsm_v2_cluster" "hsm_cluster" {
  hsm_type   = "hsm1.medium"
  subnet_ids = [
    module.network.private_a_id,
    module.network.private_b_id
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
