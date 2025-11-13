locals {
  restic_backup_hosts = [
    # servers
    "oci-03",
    "rofl-10",
    "rofl-11",
    "rofl-12",
    # laptops
    "ge2",
    "gk4",
    "x13"
  ]
}

resource "healthchecksio_check" "restic_backup" {
  for_each = toset(local.restic_backup_hosts)

  name = "Restic Backup ${each.value}"
  slug = "restic-backup-${replace(each.value, "_", "-")}"

  channels = [
    # email + discord
    "4eb97cbe-152c-464d-a2fb-7455375a2717",
    "7fdca605-8eee-48bf-87d3-e5546346cb41",
  ]

  tags = [
    "restic",
    each.value,
  ]

  timeout = 2 * 24 * 3600 # seconds
  grace   = 1 * 24 * 3600 # seconds

  desc = "Restic backup job for ${each.value}"
}

# vim: set ft=terraform
