# Generate KeyPair
resource "aws_key_pair" "eks_keypair" {
  key_name   = "eks-keypair"
  public_key = file("${path.module}/eks-keypair.pub")
}

# Output the key name to be used in the EKS module
output "keypair_name" {
  value = aws_key_pair.eks_keypair.key_name
}

data "aws_ami" "eks_ami" {
  most_recent = true
  owners      = ["602401143452"]  # AWS EKS AMI Owner ID

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.30-v*"] 
  }
}

# Create EC2 Launch Template with SSH Key Pair
resource "aws_launch_template" "eks_launch_template" {
  name_prefix   = "eks-launch-template"
  image_id      = data.aws_ami.eks_ami.id 
  instance_type = "t3.medium"
  user_data = base64encode(data.template_file.user_data_template.rendered)
  key_name = aws_key_pair.eks_keypair.key_name 

  # Specify the security group in the launch template
  network_interfaces {
    security_groups = [aws_security_group.eks_node_sg.id]
  }

  # Configure additional details (like EBS volumes)
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-worker"
    }
  }
}

data "template_file" "user_data_template" {
  template = file("${path.module}/user_data.sh")
}

resource "aws_eks_cluster" "my_cluster" {
  name     = "qst-demo"
  role_arn  = aws_iam_role.eks_cluster_role.arn
  version   = "1.30" 

  vpc_config {
    subnet_ids = module.vpc.public_subnets
    security_group_ids = [aws_security_group.eks_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_policy]
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_security_group" "eks_sg" {
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
     from_port   = 443
     to_port     = 443
     protocol    = "tcp"
     cidr_blocks = [module.vpc.public_subnets_cidr_blocks[0]]
   }

  # Allow traffic from the worker nodes' security group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.eks_node_sg.id]
    description = "Allow traffic from worker nodes"
  }
}

data "aws_launch_template" "eks_latest_template" {
  name = aws_launch_template.eks_launch_template.name
}

# Create a Security Group for EKS Node Group
resource "aws_security_group" "eks_node_sg" {
  name        = "qst-eks-node-sg"
  description = "Security group for EKS node group allowing SSH access"
  vpc_id      = module.vpc.vpc_id  

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow traffic from Prometheus"
  }
 
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Get pod logs using kubectl"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-node-sg"
  }
}

resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "qst-nodes-group"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids = module.vpc.public_subnets
  
  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  launch_template {
    id      = aws_launch_template.eks_launch_template.id
    version = data.aws_launch_template.eks_latest_template.latest_version
    # version = "$Latest"
  }

  depends_on = [aws_eks_cluster.my_cluster]
}

resource "null_resource" "update_configmap" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.node_group_role.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
EOT
  }

  depends_on = [aws_eks_cluster.my_cluster]
}


resource "aws_iam_role" "node_group_role" {
  name = "eks-node-group-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "AmazonEBSCSIDriverPolicyy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy" "ebs_permissions" {
  name   = "EBSPermissions"
  role   = aws_iam_role.node_group_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:ModifyVolume",
          "ec2:DescribeSnapshots",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CopySnapshot",
          "ec2:CreateTags"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM Policy for editing aws-auth configmap
resource "aws_iam_policy" "edit_aws_auth" {
  name        = "EditAwsAuthConfigMap"
  description = "Allows editing of aws-auth configmap"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateClusterConfig",
          "eks:ListUpdates",
          "eks:ListNodegroups"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "attach_edit_policy" {
  user       = "mohd.meesam"
  policy_arn  = aws_iam_policy.edit_aws_auth.arn
}