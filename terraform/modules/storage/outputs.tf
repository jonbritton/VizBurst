output "assets_bucket" {
  description = "Name of the asset-library bucket."
  value       = aws_s3_bucket.this["assets"].bucket
}

output "assets_bucket_arn" {
  value = aws_s3_bucket.this["assets"].arn
}

output "frames_bucket" {
  description = "Name of the rendered-frames output bucket."
  value       = aws_s3_bucket.this["frames"].bucket
}

output "frames_bucket_arn" {
  value = aws_s3_bucket.this["frames"].arn
}

output "installers_bucket" {
  description = "Name of the DCC-installers bucket (consumed by Packer builds)."
  value       = aws_s3_bucket.this["installers"].bucket
}

output "installers_bucket_arn" {
  value = aws_s3_bucket.this["installers"].arn
}
