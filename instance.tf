# Generate KeyPair
resource "aws_key_pair" "instance_keypair" {
  key_name   = "demo-keypair"
  public_key = file("${path.module}/eks-keypair.pub")
}

# Output the key name to be used in the EKS module
output "instance_keypair_name" {
  value = aws_key_pair.instance_keypair.key_name
}

data "aws_ami" "oracle_linux_uek" {
  most_recent = true

  filter {
    name   = "name"
    values = ["TechnologyLeadershipOL9-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["aws-marketplace"]
}

output "latest_oracle_linux_uek_ami" {
  value = data.aws_ami.oracle_linux_uek.id
}

# Create a security group to allow SSH
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = module.vpc.vpc_id

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

data "aws_ssm_parameter" "ec2_user_password" {
  name            = "EC2_USER_PASSWORD"     # The name of the parameter
  with_decryption = true                    # Decrypt the value since it's a SecureString
}

# Create an EC2 instance
resource "aws_instance" "oracle_linux" {
  ami           = data.aws_ami.oracle_linux_uek.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.eks_keypair.key_name  # Replace with your SSH key name
  subnet_id     = module.vpc.public_subnets[0]
  user_data     = <<-EOF
                  #!/bin/bash

                  # Update the package manager
                  yum update -y

                  # Fetch the value of ec2-user passwrod from the AWS parameter store and change user's password
                  echo "ec2-user:${data.aws_ssm_parameter.ec2_user_password.value}" | sudo chpasswd

                  # Add ec2-user to the wheel group which has the sudo permissions.
                  # This is required to apply the RHEL9-CIS policy as while applying the policy, it will require the sudo permissions for 
                  # ec2-user and and the policy will revert any change to /etc/sudoers file automatically through ansible run.
                  sudo usermod -aG wheel ec2-user
                  EOF

  root_block_device {
    volume_size = 14  # 14GB disk space
  }

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "OracleLinuxUEK-CIS"
  }
}

# Output public IP for Ansible connection
output "instance_public_ip" {
  value = aws_instance.oracle_linux.public_ip
}

# Automatically update the Ansible inventory file
resource "null_resource" "update_inventory" {
  provisioner "local-exec" {
    command = <<EOT
    sed -i '' 's/ansible_host=[^ ]*/ansible_host=${aws_instance.oracle_linux.public_ip}/' ./inventory
    EOT
  }
  depends_on = [ aws_instance.oracle_linux ]
}