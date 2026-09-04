# --- Bastion host: única forma de administrar el cluster ahora que el
#     endpoint de EKS es privado. Sin SSH ni puertos de entrada — acceso
#     vía SSM Session Manager (IAM + auditado en CloudTrail, sin llaves). ---

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
  vpc_id      = aws_vpc.main.id

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

# El SG que EKS crea automáticamente para el control plane solo deja
# pasar tráfico de los nodos. Sin esta regla, el bastion no puede llegar
# al endpoint privado del API aunque esté en la misma VPC.
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

# Permiso gestionado estándar para que el agente SSM funcione.
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Permiso mínimo extra (no viene en ninguna policy gestionada): poder
# describir ESTE cluster puntual para generar el kubeconfig localmente.
# El acceso real a los objetos de Kubernetes lo sigue controlando el RBAC
# del cluster (EKS access entries / aws-auth) — eso es un paso aparte,
# pendiente para cuando el cluster exista de verdad.
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
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Sin key_name a propósito: nada de SSH, solo SSM Session Manager.

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
