output "rofl_02_boot_volume_id" {
  value       = openstack_blockstorage_volume_v3.rofl_02_boot_volume.id
  description = "Volume ID of the root volume of rofl-02"
}

output "rofl_02_fip" {
  value       = openstack_networking_floatingip_v2.rofl_02_fip.address
  description = "Floating IP address of rofl-02"
}

# vim: set ft=terraform
