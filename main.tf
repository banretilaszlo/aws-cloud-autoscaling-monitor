module "network" {
  source = "./modules/network"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  project     = var.project
  environment = var.environment
}


module "compute" {
  source = "./modules/compute"

  vpc_id              = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  ami_id        = var.ami_id
  instance_type= var.instance_type
  user_data     = file("user-data.sh")

  project      = var.project
  environment  = var.environment

  aws_region = var.aws_region
}

module "monitoring" {
  source      = "./modules/monitoring"

  asg_name    = module.compute.asg_name
  sns_email   = var.alert_email

  project     = var.project
  environment = var.environment
}
