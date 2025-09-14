output "rofl-10_fip" {
  value       = openstack_networking_floatingip_v2.rofl-10_fip.address
  description = "Floating IP address of rofl-10"
}

# vim: set ft=terraform
