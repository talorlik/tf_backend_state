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

variable "resource_alias" {
    description = "My name"
    type        = string
}

variable "principal_arn" {
    description = "My ARN"
    type        = string
}