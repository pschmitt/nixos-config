resource "openstack_networking_port_v2" "roflport" {
  name           = "roflport"
  network_id     = openstack_networking_network_v2.roflnet.id
  admin_state_up = true
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet_v4.id
  }
}

resource "openstack_networking_network_v2" "roflnet" {
  name           = "roflnet"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "roflsubnet_v4" {
  name       = "roflsubnet-v4"
  network_id = openstack_networking_network_v2.roflnet.id
  cidr       = "10.69.42.0/24"
  ip_version = 4
}

resource "openstack_networking_subnet_v2" "roflsubnet_v6" {
  name              = "roflsubnet-v6"
  network_id        = openstack_networking_network_v2.roflnet.id
  cidr              = "2001:db8::/64" # Replace with your IPv6 range
  ip_version        = 6
  ipv6_address_mode = "slaac" # or dhcpv6-stateful, dhcpv6-stateless
  ipv6_ra_mode      = "slaac" # or dhcpv6-stateful, dhcpv6-stateless
}

resource "openstack_networking_router_v2" "roflrouter" {
  name                = "roflrouter"
  admin_state_up      = true
  external_network_id = var.provider_network_id
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = openstack_networking_router_v2.roflrouter.id
  subnet_id = openstack_networking_subnet_v2.roflsubnet_v4.id
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
