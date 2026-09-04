resource "aws_eks_cluster" "main" {
  name     = "secure-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  version = "1.31"

  vpc_config {
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    # Endpoint del API sin salida a internet: solo administrable desde
    # dentro de la VPC (bastion host o VPN). Ver README para el porqué.
    endpoint_public_access  = false
    endpoint_private_access = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name  = aws_eks_cluster.main.name
  node_role_arn = aws_iam_role.eks_nodes.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  capacity_type  = "SPOT"
  instance_types = ["t3.medium"] 

  scaling_config {
    desired_size = 1 
    max_size     = 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_contregistry_policy,
    aws_iam_role_policy_attachment.eks_node_worker_policy
  ]
}
