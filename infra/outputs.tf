output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "bastion_instance_id" {
  description = "Para conectarse: aws ssm start-session --target <id> --profile personal"
  value       = module.eks.bastion_instance_id
}
