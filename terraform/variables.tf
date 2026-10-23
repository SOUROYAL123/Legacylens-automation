variable "aws_region" {
  type        = string
  description = "AWS Region for deployment"
  default     = "ap-south-1"
}

variable "vpc_alpha_cidr" {
  type        = string
  description = "CIDR block for Consumer VPC (VPC-Alpha)"
  default     = "10.37.0.0/16"
}

variable "vpc_beta_cidr" {
  type        = string
  description = "CIDR block for Producer VPC (VPC-Beta / LegacyLens)"
  default     = "10.38.0.0/16"
}

variable "aws_organization_id" {
  type        = string
  description = "Your AWS Organization ID (e.g., o-exampleorgid)"
  default     = "o-exampleorgid"
}