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
