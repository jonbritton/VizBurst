output "launch_template_ids" {
  description = "Map of worker class => launch template ID (referenced in the Spot Event Plugin fleet config)."
  value       = { for k, lt in aws_launch_template.worker : k => lt.id }
}

output "ami_parameter_names" {
  description = "Map of worker class => SSM parameter the Packer pipeline promotes AMI IDs into."
  value       = { for k, p in aws_ssm_parameter.worker_ami : k => p.name }
}

output "worker_role_arn" {
  value = aws_iam_role.worker.arn
}

output "worker_instance_profile_arn" {
  description = "Instance profile ARN for the SEP fleet config."
  value       = aws_iam_instance_profile.worker.arn
}

output "spot_fleet_role_arn" {
  description = "IAM Fleet Role ARN for the SEP fleet config."
  value       = aws_iam_role.spot_fleet.arn
}

output "sep_user_name" {
  description = "IAM user the on-prem Spot Event Plugin authenticates as. Create its access key manually (keeps the secret out of Terraform state)."
  value       = aws_iam_user.spot_event_plugin.name
}
