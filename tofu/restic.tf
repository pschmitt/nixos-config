locals {
  restic_hosts = [
    # nixos servers
    "oci-03",
    "rofl-10",
    "rofl-11",
    "rofl-12",

    # laptops
    "ge2",
    "gk4",
    "x13",
  ]

  autorestic_hosts = [
    "fnuc",
    "oci-01",
  ]

  restic_remote_hosts = [
    "turris",
  ]

  all_restic_hosts = sort(distinct(concat(
    local.restic_hosts,
    local.autorestic_hosts,
    local.restic_remote_hosts,
  )))
}

module "restic_wasabi" {
  source = "./modules/wasabi"
  region = var.wasabi_region
  hosts  = local.all_restic_hosts
}

resource "healthchecksio_check" "restic_backup" {
  for_each = toset(local.all_restic_hosts)

  name = "${contains(local.restic_remote_hosts, each.value) ? "Restic Remote" : contains(local.autorestic_hosts, each.value) ? "Autorestic" : "Restic"} Backup ${each.value}"
  slug = "restic-backup-${replace(each.value, "_", "-")}"

  channels = [
    # email + discord
    "4eb97cbe-152c-464d-a2fb-7455375a2717",
    "7fdca605-8eee-48bf-87d3-e5546346cb41",
  ]

  tags = compact([
    contains(local.autorestic_hosts, each.value) ? "autorestic" : "restic",
    contains(local.restic_remote_hosts, each.value) ? "restic-remote" : null,
    each.value,
  ])

  # 2 days timeout + 1 day grace period
  timeout = 2 * 24 * 3600
  grace   = 1 * 24 * 3600

  desc = "Restic backup job for ${each.value}"
}

output "bucket_urls" {
  value = module.restic_wasabi.bucket_urls
}

output "access_key_ids" {
  value     = module.restic_wasabi.access_key_ids
  sensitive = true
}

output "access_key_secrets" {
  value     = module.restic_wasabi.access_key_secrets
  sensitive = true
}

output "ping_url" {
  value = { for host, check in healthchecksio_check.restic_backup : host => check.ping_url }
}

# vim: set ft=terraform :
