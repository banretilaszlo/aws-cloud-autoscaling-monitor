variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/stage/prod)"
  type        = string
}

# ---------- NETWORK ----------

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (2 AZs)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (2 AZs)"
  type        = list(string)
}


# ---------- COMPUTE ----------

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

# ---------- MONITORING ----------

variable "alert_email" {
  description = "Email address for scaling alerts"
  type        = string
}
