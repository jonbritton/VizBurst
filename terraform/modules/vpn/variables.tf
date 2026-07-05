variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "studio_public_ip" {
  description = "Static public IP of the studio firewall that terminates the VPN."
  type        = string
}

variable "onprem_cidrs" {
  description = "Studio-side CIDR(s) reachable over the VPN (render subnet, license servers, RCS host)."
  type        = list(string)
}

variable "private_route_table_id" {
  description = "Route table that should learn the on-prem routes."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
