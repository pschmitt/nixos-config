locals {
  restic_backup_hosts = [
    "oci-03",
    "rofl-10",
    "rofl-11",
    "rofl-12",
    "rofl-13",
  ]
}

resource "healthchecksio_check" "restic_backup" {
  for_each = toset(local.restic_backup_hosts)

  name = "Restic Backup ${each.value}"
  slug = "restic-backup-${replace(each.value, "_", "-")}"

  tags = [
    "restic",
    each.value,
  ]

  timeout = 2 * 24 * 3600 # seconds
  grace   = 1 * 24 * 3600 # seconds

  desc = "Restic backup job for ${each.value}"
}

# vim: set ft=terraform
