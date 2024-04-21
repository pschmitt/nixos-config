output "rofl_02_boot_volume_id" {
  value       = openstack_blockstorage_volume_v3.rofl_02_boot_volume.id
  description = "Volume ID of the root volume of rofl-02"
}

output "rofl_02_fip" {
  value       = openstack_networking_floatingip_v2.rofl_02_fip.address
  description = "Floating IP address of rofl-02"
}

output "rofl_03_boot_volume_id" {
  value       = openstack_blockstorage_volume_v3.rofl_03_boot_volume.id
  description = "Volume ID of the root volume of rofl-03"
}

output "rofl_03_fip" {
  value       = openstack_networking_floatingip_v2.rofl_03_fip.address
  description = "Floating IP address of rofl-03"
}

output "oci_03_public_ip" {
  value       = oci_core_instance.oci_03.public_ip
  description = "Public IP address of oci-03"
}

# vim: set ft=terraform
