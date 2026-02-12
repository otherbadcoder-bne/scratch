variable "domain_name" {
  description = "Domain name for the Wiki.js site (e.g. wiki.example.com)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the shared services VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the Wiki.js server"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "Environment name used for tagging"
  type        = string
  default     = "shared-services"
}
