output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name (open this in a browser)"
  value       = module.compute.alb_dns_name
}
