############################################
# Provider requirements
############################################
terraform {
  required_providers {
    wasabi = {
      source  = "thesisedu/wasabi"
      version = "~> 4.1"
    }
  }
}

############################################
# Variables
############################################
variable "hosts" {
  description = "Hostnames to provision (e.g., [\"rofl-10\", \"rofl-11\", ...])"
  type        = list(string)
}

variable "bucket_prefix" {
  description = "Prefix used for bucket names"
  type        = string
  default     = "restic-backup"
}

variable "versioning_enabled" {
  description = "Enable versioning on buckets"
  type        = bool
  default     = false
}

variable "restic_group_name" {
  description = "Name of the Wasabi group that owns RW policies"
  type        = string
  default     = "restic"
}

# Non-Tofu managed members that must remain in the group.
variable "static_group_members" {
  type        = list(string)
  default     = [
    "autorestic",
    "restic-fnuc",
    "restic-ge2",
    "restic-oci-01",
    "restic-oci-03",
    "restic-rofl-03",
    "restic-rofl-08",
    "restic-rofl-09",
    "restic-turris",
    "restic-wrt1900ac",
    "restic-x13",
  ]
}

############################################
# Group (single)
############################################
resource "wasabi_group" "restic" {
  name = var.restic_group_name
}

############################################
# Per-host resources
############################################
locals {
  # Normalize host list to a set for for_each
  host_set = toset(var.hosts)
}

# Bucket per host
resource "wasabi_bucket" "host" {
  for_each = local.host_set

  bucket = "${var.bucket_prefix}-${each.value}"
  acl    = "private"

  versioning {
    enabled = var.versioning_enabled
  }
}

# Per-host RW policy bound to that bucket (+ ListAllMyBuckets)
resource "wasabi_policy" "host_rw" {
  for_each = local.host_set

  name = "restic-${each.value}-rw"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "arn:aws:s3:::*"
      },
      {
        Effect   = "Allow"
        Action   = [
          # If you want least-privilege, replace "s3:*" with explicit actions:
          # "s3:ListBucket","s3:GetBucketLocation",
          # "s3:GetObject","s3:PutObject","s3:DeleteObject","s3:AbortMultipartUpload"
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::${wasabi_bucket.host[each.key].bucket}",
          "arn:aws:s3:::${wasabi_bucket.host[each.key].bucket}/*"
        ]
      }
    ]
  })
}

# Per-host user (e.g. restic-rofl-10)
resource "wasabi_user" "host" {
  for_each = local.host_set
  name     = "restic-${each.value}"
}

# Attach the per-host policy directly to the user
resource "wasabi_user_policy_attachment" "host_rw" {
  for_each   = local.host_set
  user       = wasabi_user.host[each.key].name
  policy_arn = wasabi_policy.host_rw[each.key].arn
}

# Per-host access key
resource "wasabi_access_key" "host" {
  for_each = local.host_set
  user     = wasabi_user.host[each.key].name
  status   = "Active"
  # Optional: if provider supports PGP, uncomment to encrypt the secret
  # pgp_key = file("pgp-public-key.asc")
}

############################################
# Group membership (single resource owns full list)
############################################
# Compose the full membership: static + all Terraform-managed users
locals {
  managed_usernames = [for k, u in wasabi_user.host : u.name]
  desired_members   = sort(distinct(concat(var.static_group_members, local.managed_usernames)))
}

resource "wasabi_group_membership" "restic_members" {
  name  = var.restic_group_name
  group = wasabi_group.restic.name
  users = local.desired_members
}

############################################
# Outputs as maps keyed by host
############################################
output "bucket_names" {
  value = { for k, b in wasabi_bucket.host : k => b.bucket }
}

output "usernames" {
  value = { for k, u in wasabi_user.host : k => u.name }
}

output "access_key_ids" {
  value     = { for k, ak in wasabi_access_key.host : k => ak.id }
  sensitive = true
}

output "access_key_secrets" {
  value     = { for k, ak in wasabi_access_key.host : k => ak.secret }
  sensitive = true
}
