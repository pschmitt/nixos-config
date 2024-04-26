resource "openstack_networking_network_v2" "better_rofl_net" {
  name           = "better-roflnet"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "better_rofl_subnet_v4" {
  name       = "better-rofl-subnet-v4"
  network_id = openstack_networking_network_v2.better_rofl_net.id
  cidr       = "10.69.43.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "better_rofl_router" {
  name                = "better-rofl-router"
  admin_state_up      = true
  external_network_id = var.provider_network_id
}

resource "openstack_networking_router_interface_v2" "better_router_interface_v4" {
  router_id = openstack_networking_router_v2.better_rofl_router.id
  subnet_id = openstack_networking_subnet_v2.better_rofl_subnet_v4.id
}

# vim: set ft=terraform
