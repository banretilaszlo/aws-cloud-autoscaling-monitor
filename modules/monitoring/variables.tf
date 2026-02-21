variable "project" {}
variable "environment" {}

variable "asg_name" {
  description = "Name of Auto Scaling Group to monitor"
}

variable "sns_email" {
  description = "Email for scale notifications"
}
