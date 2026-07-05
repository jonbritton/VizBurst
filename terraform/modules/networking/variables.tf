variable "name_prefix" {
  description = "Prefix for naming/tagging all resources (e.g. render-farm-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap the studio network."
  type        = string
}

variable "public_subnets" {
  description = "Map of availability zone => public subnet CIDR (Packer build tier)."
  type        = map(string)
}

variable "private_subnets" {
  description = "Map of availability zone => private subnet CIDR (worker tier)."
  type        = map(string)
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
