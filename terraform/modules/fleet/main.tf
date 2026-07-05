# Everything the Spot Event Plugin needs to run the cloud fleet:
# launch templates (CPU + GPU), the worker instance role, the Spot Fleet
# service role, and the IAM identity the on-prem plugin authenticates as.
#
# Instance *types* are deliberately absent from the launch templates — the
# Spot Event Plugin's fleet config picks types per group, and listing several
# (deep pools) is how we keep GPU interruption rates tolerable.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- AMI promotion parameters ---
# The Packer pipeline writes the promoted AMI ID here; launch templates
# resolve it at launch time, so promotion never touches Deadline or Terraform.

resource "aws_ssm_parameter" "worker_ami" {
  for_each = var.worker_classes

  name  = "/${var.name_prefix}/ami/${each.key}-worker"
  type  = "String"
  value = "ami-PLACEHOLDER-set-by-packer-pipeline"

  tags = var.tags

  lifecycle {
    # The CI pipeline owns the value after first apply.
    ignore_changes = [value]
  }
}

# --- Worker instance role ---
# Workers can read the asset library and write frames. That's it: no SSM
# (admin is SSH over the VPN), no internet, no wildcard S3.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.name_prefix}-worker"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name_prefix}-worker"
  role = aws_iam_role.worker.name
}

data "aws_iam_policy_document" "worker_s3" {
  statement {
    sid       = "ListTransferBuckets"
    actions   = ["s3:ListBucket"]
    resources = [var.assets_bucket_arn, var.frames_bucket_arn]
  }

  statement {
    sid       = "ReadAssets"
    actions   = ["s3:GetObject"]
    resources = ["${var.assets_bucket_arn}/*"]
  }

  statement {
    sid       = "WriteFrames"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${var.frames_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "worker_s3" {
  name   = "s3-transfer-lane"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker_s3.json
}

# --- Launch templates ---

resource "aws_launch_template" "worker" {
  for_each = var.worker_classes

  name        = "${var.name_prefix}-${each.key}-worker"
  description = "Deadline ${upper(each.key)} render worker (launched by the Spot Event Plugin)"

  # Resolved at launch: promotion = updating the SSM parameter.
  image_id = "resolve:ssm:${aws_ssm_parameter.worker_ami[each.key].name}"

  key_name = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  vpc_security_group_ids = [var.workers_sg_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = each.value.root_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  # Detailed monitoring costs money and Deadline Monitor is the pane of glass.
  monitoring {
    enabled = false
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])
    content {
      resource_type = tag_specifications.value
      tags = merge(var.tags, {
        Name          = "${var.name_prefix}-${each.key}-worker"
        DeadlineGroup = "aws-${each.key}"
      })
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-worker" })
}

# --- Spot Fleet service role ---
# Spot Fleet assumes this to tag and manage the instances it launches.

data "aws_iam_policy_document" "spotfleet_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["spotfleet.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "spot_fleet" {
  name               = "${var.name_prefix}-spot-fleet"
  assume_role_policy = data.aws_iam_policy_document.spotfleet_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "spot_fleet_tagging" {
  role       = aws_iam_role.spot_fleet.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# --- Spot Event Plugin identity ---
# The plugin runs on-prem, so it can't use an instance profile or OIDC — an
# IAM user is the pragmatic option. The access key is deliberately NOT created
# here (it would land in Terraform state): create it in the console or with
#   aws iam create-access-key --user-name <this user>
# and put it straight into the Deadline SEP config.

resource "aws_iam_user" "spot_event_plugin" {
  name = "${var.name_prefix}-deadline-sep"
  tags = var.tags
}

data "aws_iam_policy_document" "sep" {
  statement {
    sid = "FleetManagement"
    actions = [
      "ec2:RequestSpotFleet",
      "ec2:ModifySpotFleetRequest",
      "ec2:CancelSpotFleetRequests",
      "ec2:CreateFleet",
      "ec2:DeleteFleets",
      "ec2:CreateTags",
      "ec2:DescribeSpotFleetRequests",
      "ec2:DescribeSpotFleetInstances",
      "ec2:DescribeFleets",
      "ec2:DescribeFleetInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # Terminate only instances that belong to a Spot fleet — not, say, the RCS.
  statement {
    sid       = "TerminateFleetInstancesOnly"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/aws:ec2spot:fleet-request-id"
      values   = ["*"]
    }
  }

  statement {
    sid     = "PassFleetAndWorkerRoles"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.spot_fleet.arn,
      aws_iam_role.worker.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "spotfleet.amazonaws.com"]
    }
  }
}

resource "aws_iam_user_policy" "sep" {
  name   = "spot-event-plugin"
  user   = aws_iam_user.spot_event_plugin.name
  policy = data.aws_iam_policy_document.sep.json
}
