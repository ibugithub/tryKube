# Output public IP
output "ec2_public_ip" {
  value = aws_instance.cloudhsm_host.public_ip
}
