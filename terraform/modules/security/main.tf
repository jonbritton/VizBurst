# --- Render workers ---
# Workers have no internet path at all. Their entire world is:
#   - on-prem over the VPN (RCS, license servers, inbound SSH/Ansible)
#   - S3 through the gateway endpoint (assets in, frames out)
#   - the VPC itself (DNS is exempt from SG filtering, but keep intra-VPC open)

resource "aws_security_group" "workers" {
  name        = "${var.name_prefix}-workers"
  description = "Deadline render workers (Spot fleet)"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-workers" })
}

# Inbound: administration from the studio only.
resource "aws_vpc_security_group_ingress_rule" "workers_ssh_onprem" {
  for_each = toset(var.onprem_cidrs)

  security_group_id = aws_security_group.workers.id
  description       = "SSH/Ansible from the studio over the VPN"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "workers_icmp_onprem" {
  for_each = toset(var.onprem_cidrs)

  security_group_id = aws_security_group.workers.id
  description       = "Ping from the studio (tunnel debugging)"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = each.value
}

# Outbound: on-prem (RCS, sesinetd, RLM — ports vary by daemon, so all
# protocols to the studio CIDR rather than a brittle port list)...
resource "aws_vpc_security_group_egress_rule" "workers_onprem" {
  for_each = toset(var.onprem_cidrs)

  security_group_id = aws_security_group.workers.id
  description       = "Deadline RCS + license servers over the VPN"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}

# ...S3 via the gateway endpoint...
resource "aws_vpc_security_group_egress_rule" "workers_s3" {
  security_group_id = aws_security_group.workers.id
  description       = "S3 gateway endpoint (assets/frames)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = var.s3_prefix_list_id
}

# ...and the VPC itself.
resource "aws_vpc_security_group_egress_rule" "workers_vpc" {
  security_group_id = aws_security_group.workers.id
  description       = "Intra-VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}
