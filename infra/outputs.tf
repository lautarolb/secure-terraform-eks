# Outputs del stack de red. Los vamos a usar cuando llegue EKS (necesita
# el vpc_id y las subnets donde correr los nodos).

output "vpc_id" {
   value =  aws_vpc.main.id
}

output "private_subnet_ids" {
   value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "public_subnet_ids" {
   value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

