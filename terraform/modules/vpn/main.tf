# Site-to-Site VPN: the only bridge between the studio and AWS.
# Carries Deadline RCS traffic, license checkouts, and SSH — render data
# goes over the S3 gateway endpoint instead and never touches this link.
#
# Static routing: works on any IPsec-capable firewall, no BGP daemon to run.
# If the studio device turns out to speak BGP, flip static_routes_only and
# set customer_gateway bgp_asn — the VPN itself doesn't need rebuilding.

resource "aws_vpn_gateway" "this" {
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-vgw" })
}

resource "aws_customer_gateway" "studio" {
  ip_address = var.studio_public_ip
  type       = "ipsec.1"
  # Required by the API even for static routing; unused until/unless BGP.
  bgp_asn = 65000

  tags = merge(var.tags, { Name = "${var.name_prefix}-studio-cgw" })
}

resource "aws_vpn_connection" "studio" {
  vpn_gateway_id      = aws_vpn_gateway.this.id
  customer_gateway_id = aws_customer_gateway.studio.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-studio-vpn" })
}

# Tell AWS which prefixes live on the studio side.
resource "aws_vpn_connection_route" "onprem" {
  for_each = toset(var.onprem_cidrs)

  vpn_connection_id      = aws_vpn_connection.studio.id
  destination_cidr_block = each.value
}

# Propagate the on-prem routes into the private (worker) route table.
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = var.private_route_table_id
}
