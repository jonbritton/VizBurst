# --- Configure these on the studio firewall ---

output "vpn_tunnel_addresses" {
  description = "AWS tunnel endpoints for the studio firewall. Pre-shared keys: AWS console -> VPN connection -> Download configuration."
  value = {
    tunnel1 = module.vpn.tunnel1_address
    tunnel2 = module.vpn.tunnel2_address
  }
}

# --- Paste these into the Spot Event Plugin config in Deadline Monitor ---

output "sep_launch_template_ids" {
  value = module.fleet.launch_template_ids
}

output "sep_fleet_role_arn" {
  value = module.fleet.spot_fleet_role_arn
}

output "sep_worker_instance_profile_arn" {
  value = module.fleet.worker_instance_profile_arn
}

output "sep_iam_user" {
  description = "Create this user's access key manually (aws iam create-access-key) so the secret stays out of state."
  value       = module.fleet.sep_user_name
}

output "worker_subnet_ids" {
  value = module.networking.private_subnet_ids
}

# --- CI / pipeline wiring ---

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}

output "ami_builder_instance_profile" {
  value = module.github_oidc.ami_builder_instance_profile_name
}

output "ami_parameter_names" {
  value = module.fleet.ami_parameter_names
}

output "packer_build_subnet_id" {
  description = "Public subnet Packer should build in."
  value       = module.networking.public_subnet_ids[0]
}

# --- Sync script wiring ---

output "assets_bucket" {
  value = module.storage.assets_bucket
}

output "frames_bucket" {
  value = module.storage.frames_bucket
}

output "installers_bucket" {
  value = module.storage.installers_bucket
}
