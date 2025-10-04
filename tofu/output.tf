output "rofl-10_fip" {
  value       = openstack_networking_floatingip_v2.rofl-10_fip.address
  description = "Floating IP address of rofl-10"
}

output "restic_backup_ping_urls" {
  description = "Ping URLs for Restic backup checks"
  value       = { for host, check in healthchecksio_check.restic_backup : host => check.ping_url }
}

# vim: set ft=terraform
