module "network" {
  source = "./modules/network"

  vpc_cidr = var.vpc_cidr
}

module "iam" {
  source = "./modules/iam"
}

module "eks" {
  source = "./modules/eks"

  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  cluster_role_arn    = module.iam.cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
}
