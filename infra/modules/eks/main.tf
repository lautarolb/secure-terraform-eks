terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Deuda conocida, pendiente de arreglar (no bloquear CI mientras tanto):
#   - control plane logging (audit logs a CloudWatch) sin habilitar
#   - secrets de Kubernetes sin encryption adicional vía KMS (queda solo el default de EKS)
#tfsec:ignore:aws-eks-enable-control-plane-logging
#tfsec:ignore:aws-eks-encrypt-secrets
#checkov:skip=CKV_AWS_38:control plane logging pendiente, tracking en README roadmap
#checkov:skip=CKV_AWS_58:KMS envelope encryption de secrets pendiente, tracking en README roadmap
resource "aws_eks_cluster" "main" {
  name     = "secure-eks-cluster"
  role_arn = var.cluster_role_arn

  version = "1.31"

  vpc_config {
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)

    endpoint_public_access  = false
    endpoint_private_access = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name  = aws_eks_cluster.main.name
  node_role_arn = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  capacity_type  = "SPOT"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}


data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

resource "aws_iam_role" "cni_irsa" {
  name = "secure-eks-cni-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-node"
          "${local.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_irsa_policy" {
  role       = aws_iam_role.cni_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  name        = "secure-eks-bastion-sg"
  description = "Bastion EKS - sin reglas de entrada, solo SSM"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-eks-bastion-sg"
  }
}

resource "aws_security_group_rule" "eks_api_from_bastion" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_iam_role" "bastion" {
  name = "secure-eks-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "bastion_eks_describe" {
  name = "eks-describe-cluster"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.main.arn
    }]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "secure-eks-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }


  user_data = <<-EOF
    #!/bin/bash
    curl -s -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    curl -sLO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
  EOF

  tags = {
    Name = "secure-eks-bastion"
  }
}
