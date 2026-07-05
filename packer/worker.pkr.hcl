# Render worker AMI: Ubuntu + the same Ansible roles that configure the
# on-prem nodes. Built in the public subnet (the only tier with internet),
# with the ami-builder instance profile for installer-bucket reads.
#
# One image serves both fleets — the NVIDIA driver idles on CPU instances.

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "name_prefix" {
  type    = string
  default = "render-farm-dev"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet to build in (resolved by scripts/packer_env.sh)."
}

variable "installers_bucket" {
  type        = string
  description = "S3 bucket holding the DCC installers (resolved by scripts/packer_env.sh)."
}

variable "instance_type" {
  type = string
  # CPU-heavy build (driver DKMS compile, DCC extraction) — no GPU needed.
  default = "c6i.2xlarge"
}

data "amazon-ami" "ubuntu" {
  region      = var.region
  owners      = ["099720109477"] # Canonical
  most_recent = true

  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }
}

source "amazon-ebs" "worker" {
  region        = var.region
  source_ami    = data.amazon-ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  associate_public_ip_address = true
  iam_instance_profile        = "${var.name_prefix}-ami-builder"

  ssh_username = "ubuntu"

  ami_name        = "${var.name_prefix}-worker-{{timestamp}}"
  ami_description = "Deadline render worker (Houdini/Blender/Nuke) — built by ami-build.yaml"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 60
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name      = "${var.name_prefix}-worker"
    Role      = "render-worker"
    ManagedBy = "packer"
    BaseAMI   = "{{ .SourceAMI }}"
  }

  snapshot_tags = {
    Name = "${var.name_prefix}-worker"
  }

  run_tags = {
    Name = "${var.name_prefix}-ami-build"
  }
}

build {
  sources = ["source.amazon-ebs.worker"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbooks/worker.yml"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "aws_worker=true installers_bucket=${var.installers_bucket}",
    ]
  }

  # Smoke check: existence only — no license contact, no GPU on the builder.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '--- smoke check ---'",
      "test -x /opt/Thinkbox/Deadline10/bin/deadlineworker",
      "test -x /usr/local/bin/blender",
      "test -e /opt/hfs",
      "aws --version",
      "s5cmd version",
      "dpkg -l | grep -q nvidia-driver && echo 'nvidia driver present'",
      "echo '--- smoke check passed ---'",
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/packer-manifest.json"
  }
}
