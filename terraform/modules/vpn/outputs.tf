output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection."
  value       = aws_vpn_connection.studio.id
}

output "tunnel1_address" {
  description = "Public IP of AWS tunnel endpoint 1 (configure on the studio firewall)."
  value       = aws_vpn_connection.studio.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP of AWS tunnel endpoint 2 (configure on the studio firewall)."
  value       = aws_vpn_connection.studio.tunnel2_address
}

# Pre-shared keys are intentionally NOT output here; they live in state and in
# the downloadable device config (AWS console → VPN connection → Download
# configuration), which is the sane way to configure the studio firewall.
