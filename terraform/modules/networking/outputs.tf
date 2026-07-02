output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (Packer build tier)."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (worker tier, one per AZ)."
  value       = [for s in aws_subnet.private : s.id]
}

output "private_subnet_ids_by_az" {
  description = "Map of AZ => private subnet ID (static keys for for_each consumers)."
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "private_route_table_id" {
  description = "Private route table ID (target for VPN route propagation)."
  value       = aws_route_table.private.id
}

output "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint (for security group egress rules)."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
