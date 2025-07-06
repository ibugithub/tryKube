output "ec2_instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.demo.id
}

output "ec2_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.demo.public_ip
}

output "iam_role_name" {
  description = "The name of the IAM role used by EC2"
  value       = aws_iam_role.ec2_role.name
}

output "instance_profile_name" {
  description = "The instance profile attached to EC2"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "custom_s3_policy_name" {
  description = "The name of the custom S3 policy"
  value       = aws_iam_policy.s3_specific_bucket.name
}
