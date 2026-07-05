variable "region" {
  description = "AWS region. us-west-2 for GPU Spot depth (g5/g6) and 4 AZs."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for naming/tagging all resources."
  type        = string
  default     = "render-farm-dev"
}

variable "github_repo" {
  description = "owner/repo allowed to assume the CI role via OIDC."
  type        = string
  default     = "jonbritton/VizBurst"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Confirmed non-overlapping with the studio network."
  type        = string
  default     = "10.18.0.0/16"
}

variable "public_subnets" {
  description = "AZ => CIDR for the public (Packer build) tier."
  type        = map(string)
  default = {
    "us-west-2a" = "10.18.0.0/24"
  }
}

variable "private_subnets" {
  description = "AZ => CIDR for the private (worker) tier. Three AZs = deeper Spot pools for the GPU fleet."
  type        = map(string)
  default = {
    "us-west-2a" = "10.18.10.0/24"
    "us-west-2b" = "10.18.11.0/24"
    "us-west-2c" = "10.18.12.0/24"
  }
}

# --- Studio-side facts: set these in terraform.tfvars (see the .example) ---

variable "studio_public_ip" {
  description = "Static public IP of the studio firewall terminating the Site-to-Site VPN."
  type        = string
}

variable "onprem_cidrs" {
  description = "Studio network CIDR(s) the VPN routes to: must cover the RCS host, license servers, and admin workstations."
  type        = list(string)
}
