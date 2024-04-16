resource "openstack_networking_network_v2" "roflnet" {
  name           = "roflnet"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "roflsubnet" {
  name       = "roflsubnet"
  network_id = openstack_networking_network_v2.roflnet.id
  cidr       = "10.69.42.0/24"
  ip_version = 4
}

resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  port_id     = openstack_networking_port_v2.roflport.id
}

# Legacy, deprecated
# resource "openstack_compute_floatingip_associate_v2" "fip_associate" {
#   floating_ip = openstack_networking_floatingip_v2.floating_ip.address
#   instance_id = openstack_compute_instance_v2.nixos_anywhere_vm.id
# }

output "vm_floating_ip" {
  value       = openstack_networking_floatingip_v2.floating_ip.address
  description = "Floating IP address of the deployed NixOS VM"
}

# vim: set ft=terraform
