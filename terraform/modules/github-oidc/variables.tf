variable "name_prefix" { type = string }

variable "github_repo" {
  description = "owner/repo of the GitHub repository, e.g. yourname/domify"
  type        = string
}

variable "installers_bucket_arn" {
  description = "Bucket holding DCC installers for the AMI build."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
