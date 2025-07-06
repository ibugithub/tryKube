output "vpc_id" {
  value = aws_vpc.hsm_vpc.id
}

output "private_a_id" {
  value = aws_subnet.private_a.id
}

output "private_b_id" {
  value = aws_subnet.private_b.id
}

output "ssh_sg_id" {
  value = aws_security_group.allow_ssh.id
}
