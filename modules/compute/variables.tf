variable "vpc_id" {}
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "ami_id" {}
variable "instance_type" {}

variable "user_data" {}

variable "project" {}
variable "environment" {}

variable "aws_region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
}


