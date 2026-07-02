variable "name_prefix" {
  type = string
}

variable "worker_classes" {
  description = "Worker classes to build launch templates for. Keys become Deadline group suffixes (aws-cpu, aws-gpu)."
  type = map(object({
    root_gb = number
  }))
  default = {
    cpu = { root_gb = 100 }
    gpu = { root_gb = 200 }
  }
}

variable "workers_sg_id" {
  description = "Security group for worker instances."
  type        = string
}

variable "assets_bucket_arn" {
  type = string
}

variable "frames_bucket_arn" {
  type = string
}

variable "key_name" {
  description = "EC2 key pair for SSH. Optional — the AMI bakes studio keys via Ansible, so this is a break-glass extra."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
