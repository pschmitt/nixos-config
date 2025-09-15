resource "wasabi_bucket" "deleteme-test" {
  bucket = "test-deleteme-pschmitt-lol-fart"
  acl    = "private"

  versioning {
    enabled = false
  }
}

resource "wasabi_policy" "restic_backup_test_deleteme_rw" {
  name = "restic-backup-test-deleteme-rw"
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
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${wasabi_bucket.deleteme-test.bucket}",
          "arn:aws:s3:::${wasabi_bucket.deleteme-test.bucket}/*"
        ]
      }
    ]
  })
}

resource "wasabi_user_policy_attachment" "restic_test_deleteme_rw" {
  user       = wasabi_user.restic_test_deleteme.name
  policy_arn = wasabi_policy.restic_backup_test_deleteme_rw.arn
}

resource "wasabi_user" "restic_test_deleteme" {
  name = "restic-test-deleteme"
}

resource "wasabi_group" "restic" {
  name = "restic"
}

resource "wasabi_group_membership" "restic_members" {
  name = "restic"

  group = wasabi_group.restic.name
  users = [
    # non-tofu managed group members
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

    # tofu managed group members
    wasabi_user.restic_test_deleteme.name
  ]
}

resource "wasabi_access_key" "restic_test_deleteme" {
  user   = wasabi_user.restic_test_deleteme.name
  status = "Active"
}

# --- Outputs (sensitive) ---
output "restic_test_deleteme_access_key_id" {
  value     = wasabi_access_key.restic_test_deleteme.id
  sensitive = true
}

output "restic_test_deleteme_secret" {
  value     = wasabi_access_key.restic_test_deleteme.secret
  sensitive = true
}
