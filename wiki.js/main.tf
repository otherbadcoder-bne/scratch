terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider
provider "aws" {
  region = "ap-southeast-2"
}

# CloudFront requires ACM certificates in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
