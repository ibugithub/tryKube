provider "aws" {
  region = "us-east-2"
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "rsa-key-for-terraform"
  public_key = file("${path.module}/rsa-key-for-terraform.pub")
}


resource "aws_security_group" "allow_ssh" {
  name        = "allow-ssh"
  description = "Allow SSH from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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

data "aws_vpc" "default" {
  default = true
}


resource "aws_iam_role" "ec2_role" {
  name = "ec2-le-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_specific_bucket" {
  name   = "S3AccessOnlyMyBucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ],
        Resource = "arn:aws:s3:::test-django-irsa-testing/*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "s3_custom_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_specific_bucket.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}


resource "aws_instance" "demo" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  key_name = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

    user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y nginx
              echo "<h1>Hello from Terraform EC2 with Nginx</h1>" | sudo tee /var/www/html/index.html
              sudo systemctl start nginx
              sudo systemctl enable nginx
              EOF

  tags = {
    Name = "TerraformDemoEC2"
  }
}
