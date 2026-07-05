output "role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "ami_builder_instance_profile_name" {
  description = "Instance profile Packer attaches to the temporary build instance."
  value       = aws_iam_instance_profile.ami_builder.name
}
