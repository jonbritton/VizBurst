variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "onprem_cidrs" {
  description = "Studio-side CIDR(s) allowed to administer workers and receive worker traffic."
  type        = list(string)
}

variable "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
