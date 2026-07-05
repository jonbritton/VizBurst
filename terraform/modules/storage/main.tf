# S3 transfer lane: three buckets, no filesystem.
#   assets     — content-addressed asset library, delta-synced from on-prem
#   frames     — rendered output on its way back to the studio file server
#   installers — DCC installers the Packer build pulls (not redistributable,
#                so they can't live in the public repo)
#
# The buckets are a transfer lane, not an archive: lifecycle rules expire
# frames after pickup and prune asset objects after a show goes cold. The
# on-prem file server remains the system of record.

data "aws_caller_identity" "current" {}

locals {
  # Account ID suffix keeps the names globally unique without being cute.
  buckets = {
    assets     = { expire_days = var.assets_expire_days }
    frames     = { expire_days = var.frames_expire_days }
    installers = { expire_days = null }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = "${var.name_prefix}-${each.key}-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for name, cfg in local.buckets : name => cfg if cfg.expire_days != null }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "expire-transfer-lane"
    status = "Enabled"
    filter {}

    expiration {
      days = each.value.expire_days
    }
  }

  rule {
    id     = "abort-stale-multipart"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Belt-and-braces: refuse plaintext access on every bucket.
data "aws_iam_policy_document" "tls_only" {
  for_each = aws_s3_bucket.this

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.tls_only[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
