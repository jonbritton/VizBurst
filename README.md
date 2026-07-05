# VizBurst
by Jon Britton, for the Science Visualization Studio and
   the Morrison Planetarium at the California Academy of Sciences
#

Hybrid render-farm infrastructure for the Science Visualization Studio: the existing on-prem Deadline installation, extended into AWS for burst capacity. Cloud resources are provisioned with Terraform (openTofu if we're being honest), built and validated by GitHub Actions, and scheduled by Deadline itself.

Built to interface with the Viz Studio's render farm and GPU cluster and AWS.


## Repo layout

- `.github/` —  CI pipeline
- `ansible/` — The single source of truth for worker environments: roles + version manifest, applied to on-prem nodes and consumed by the AMI build
- `deadline/` — Python submission and worker scripts, including the asset/frame sync steps
- `devopsctl/` — Python CLI for extending jobs and pulling logs/frames
- `docs/` — All the news that's fit to print.
- `packer/` — AMI build template (Ubuntu + the shared Ansible roles)
- `scripts/` — CI helpers: resolve build env by tag, promote AMIs via SSM, prune old images
- `terraform/` — modules for all our cloud provisioning components

## Architecture

- **Deadline** owns render scheduling, on-prem and in-cloud. The existing on-prem Repository remains the single source of truth for jobs, workers, and licensing.
- **EC2 Spot instances from a pre-baked AMI** run the render environment directly. The AMI is built by the same Ansible playbooks that configure the on-prem workers.
- **S3** is the transfer lane for assets in and frames out, kept fast by delta-syncing a content-addressed asset library.
- **Terraform** provisions the AWS footprint (VPC, VPN, security groups, IAM, S3, endpoints) as reusable modules.
- **GitHub Actions** lints, tests, and validates Terraform, and builds/promotes the worker AMI — authenticating to AWS via OIDC, no long-lived keys.


## Moving files: on-prem ⇄ AWS

Renders need scene files and assets going out, and finished frames coming back. The design principle: **the uplink is the bottleneck, so never send the same byte twice.**

**Outbound (assets to AWS):**
1. The S3 assets bucket is treated as a **continuously-synced, content-addressed asset library**. A manifest of file hashes is computed at publish/submit time and only objects S3 doesn't already have are uploaded. Shots in a sequence share most of their assets, so a show's first big upload happens once; subsequent shots sync a little subset.
2. The sync runs as a **Deadline job the render job depends on**, so upload overlaps with queue wait and Spot fleet spin-up instead of preceding them.
3. Uploads use high-concurrency multipart transfer (s5cmd/rclone-class tooling), with many-small-file asset sets packed into archives — single-stream copies won't saturate the link, especially on texture-heavy shots.
4. Cloud workers pull assets from S3 to **local NVMe instance storage** at task start via a **VPC gateway endpoint** (no public internet! no money down!) The local cache is keyed to the manifest hash, so an instance rendering ten tasks of one shot downloads once.

**Inbound (frames back on-prem):**
1. Workers write finished frames to an S3 output bucket as tasks complete.
2. An on-prem sync job (Deadline post-task script or scheduled pull) copies frames down to the studio file server, where artists pick them up from the same paths they always have.

**Escalation path:** for shows where huge asset sets across many nodes make per-instance copies hurt, **FSx for Lustre linked to the assets bucket** lazy-loads files on first read and shares them fleet-wide — workers start rendering before the full set lands. It reintroduces a metered managed filesystem (order of $25/day at minimum size), so it's held in reserve rather than defaulted to.

**Cost/management controls:**
- **Lifecycle rules** expire delivered frames from S3 after a short window, and asset-library objects a show no longer references get pruned at wrap. The buckets are a transfer lane and working set — the on-prem file server remains the system of record.
- Inbound frame downloads are S3 egress, the main variable cost; it scales directly with rendered output and is only incurred when rendering in the cloud.
- No always-on file gateway, no replicated filesystem in the default path: the "moving parts" are two buckets and two sync scripts.


## Environment parity: keeping the AMI and local renderers in lockstep

**one Ansible playbook, two targets.**

- All render-environment configuration lives in the `ansible/` roles, with every version that matters — DCC builds, renderer versions, Deadline client, GPU driver — pinned in a **single version manifest** (vars file). "The environment" is defined as *a git commit of the playbooks plus the manifest*. Corollary discipline: nobody hand-installs anything on a render node.
- **Packer builds the AMI** by booting a temporary EC2 instance, running that same playbook against it, and snapshotting. The build runs in GitHub Actions (existing OIDC role), triggered **only when the playbooks or manifest change** — not on a schedule. A build is ~30-60 minutes of one instance's time.
- **Promotion without touching Deadline:** the Spot Event Plugin's fleet definitions reference an EC2 **launch template**; promotion just sets the new AMI as the template's default version, and the next fleet launches on it automatically. The AMI ID is also published to an SSM parameter, making rollback a one-line pointer flip.
- **On-prem stays on the same commit:** the merge that feeds Packer also applies the playbook to the on-prem nodes over the studio network, and a periodic `ansible-playbook --check` run flags any node that has drifted between rollouts.


## Design notes

- **us-west-2 over us-west-1** — N. California has two AZs, thin Spot pools, and no g5/g6; Oregon has all three fixed, and render traffic doesn't care about 15 ms.
- **VPN over exposed RCS port** — ~$36/month buys no inbound firewall rules, no TLS certificate lifecycle, and on-prem floating licenses working in the cloud unchanged.
- **Spot over On-Demand** — renders are interruption-tolerant (Deadline requeues preempted tasks), so Spot's discount is nearly free money for this workload.
- **Scale-to-zero by default** — standing AWS costs are the VPN connection and a working set of S3 objects; everything else with an hourly meter exists only while jobs are queued.
