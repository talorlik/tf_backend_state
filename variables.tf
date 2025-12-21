variable "env" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
}

variable "prefix" {
  description = "Name added to all resources"
  type        = string
}

variable "principal_arn" {
  description = "IAM principal ARN that will have access to the S3 bucket. If not provided, defaults to the current caller's ARN (automatically detected)."
  type        = string
  default     = null
}
