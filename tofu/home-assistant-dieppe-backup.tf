############################################
# Home Assistant (dieppe) native backups
# Dedicated Wasabi bucket + RW credentials.
############################################

locals {
  homeassistant_dieppe_bucket_name = "homeassistant-dieppe"
  homeassistant_dieppe_username    = "homeassistant-dieppe"
}

# Single bucket for Home Assistant backups
resource "wasabi_bucket" "homeassistant_dieppe_backup" {
  bucket = local.homeassistant_dieppe_bucket_name
  acl    = "private"
}

# RW policy scoped to the bucket (+ ListAllMyBuckets)
resource "wasabi_policy" "homeassistant_dieppe_rw" {
  name = "homeassistant-dieppe-rw"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "arn:aws:s3:::*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::${wasabi_bucket.homeassistant_dieppe_backup.bucket}",
          "arn:aws:s3:::${wasabi_bucket.homeassistant_dieppe_backup.bucket}/*"
        ]
      }
    ]
  })
}

# Dedicated user for Home Assistant backups
resource "wasabi_user" "homeassistant_dieppe_backup" {
  name = local.homeassistant_dieppe_username
}

resource "wasabi_user_policy_attachment" "homeassistant_dieppe_rw" {
  user       = wasabi_user.homeassistant_dieppe_backup.name
  policy_arn = wasabi_policy.homeassistant_dieppe_rw.arn
}

resource "wasabi_access_key" "homeassistant_dieppe_backup" {
  user   = wasabi_user.homeassistant_dieppe_backup.name
  status = "Active"
}

output "homeassistant_dieppe_bucket_url" {
  value = "https://s3.${var.wasabi_region}.wasabisys.com/${wasabi_bucket.homeassistant_dieppe_backup.bucket}"
}

output "homeassistant_dieppe_username" {
  value = wasabi_user.homeassistant_dieppe_backup.name
}

output "homeassistant_dieppe_access_key_id" {
  value     = wasabi_access_key.homeassistant_dieppe_backup.id
  sensitive = true
}

output "homeassistant_dieppe_access_key_secret" {
  value     = wasabi_access_key.homeassistant_dieppe_backup.secret
  sensitive = true
}

# vim: set ft=terraform :
