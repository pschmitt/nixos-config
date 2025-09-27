# openstack wiit
resource "openstack_networking_network_v2" "rofl_net" {
  provider       = openstack.openstack-wiit
  name           = "rofl-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "rofl_subnet-v4" {
  provider   = openstack.openstack-wiit
  name       = "rofl-subnet"
  network_id = openstack_networking_network_v2.rofl_net.id
  cidr       = "10.69.46.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "rofl_router" {
  provider            = openstack.openstack-wiit
  name                = "rofl-router"
  admin_state_up      = true
  external_network_id = var.provider_network_id
}

resource "openstack_networking_router_interface_v2" "roflrouter-interface-v4" {
  provider  = openstack.openstack-wiit
  router_id = openstack_networking_router_v2.rofl_router.id
  subnet_id = openstack_networking_subnet_v2.rofl_subnet-v4.id
}

# vim: set ft=terraform
