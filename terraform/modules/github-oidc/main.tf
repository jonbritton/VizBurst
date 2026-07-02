data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's cert against its CA library now; the thumbprint is
  # required by the resource but effectively ignored. This is GitHub's value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Security boundary: only THIS repo's workflows can assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# --- AMI builder instance role ---
# The temporary EC2 instance Packer boots. Its one extra privilege beyond
# a vanilla instance: reading DCC installers out of the installers bucket.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ami_builder" {
  name               = "${var.name_prefix}-ami-builder"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "ami_builder" {
  name = "${var.name_prefix}-ami-builder"
  role = aws_iam_role.ami_builder.name
}

data "aws_iam_policy_document" "ami_builder_s3" {
  statement {
    sid       = "ListInstallers"
    actions   = ["s3:ListBucket"]
    resources = [var.installers_bucket_arn]
  }

  statement {
    sid       = "ReadInstallers"
    actions   = ["s3:GetObject"]
    resources = ["${var.installers_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "ami_builder_s3" {
  name   = "read-installers"
  role   = aws_iam_role.ami_builder.id
  policy = data.aws_iam_policy_document.ami_builder_s3.json
}

# --- What the CI role may do: build AMIs, promote them, nothing else ---

data "aws_iam_policy_document" "packer" {
  # Most EC2 AMI-build actions don't support resource-level scoping;
  # the region condition is the effective blast-radius control.
  statement {
    sid = "PackerBuild"
    actions = [
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ec2:CreateImage",
      "ec2:RegisterImage",
      "ec2:DeregisterImage",
      "ec2:CopyImage",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:ModifySnapshotAttribute",
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:Describe*",
      "ec2:GetPasswordData",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  statement {
    sid     = "PassBuilderRole"
    actions = ["iam:PassRole", "iam:GetInstanceProfile"]
    resources = [
      aws_iam_role.ami_builder.arn,
      aws_iam_instance_profile.ami_builder.arn,
    ]
  }

  # Promotion: the pipeline's only write outside EC2 is flipping AMI pointers.
  statement {
    sid = "PromoteAmi"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.name_prefix}/ami/*"
    ]
  }
}

resource "aws_iam_role_policy" "packer" {
  name   = "packer-ami-pipeline"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.packer.json
}
