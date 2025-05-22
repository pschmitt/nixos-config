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

# resource "openstack_networking_subnet_v2" "roflsubnet_v6" {
#   name          = "roflsubnet-v6"
#   network_id    = openstack_networking_network_v2.roflnet.id
#   subnetpool_id = openstack_networking_subnetpool_v2.customer_ipv6.id
#   ip_version    = 6
#   # options: slaac dhcpv6-stateful dhcpv6-stateless
#   ipv6_address_mode = "slaac"
#   ipv6_ra_mode      = "slaac"
# }

resource "openstack_networking_router_v2" "roflrouter" {
  name                = "roflrouter"
  admin_state_up      = true
  external_network_id = var.provider_network_id
}

resource "openstack_networking_router_interface_v2" "router_interface_v4" {
  router_id = openstack_networking_router_v2.roflrouter.id
  subnet_id = openstack_networking_subnet_v2.roflsubnet_v4.id
}

# resource "openstack_networking_router_interface_v2" "router_interface_v6" {
#   router_id = openstack_networking_router_v2.roflrouter.id
#   subnet_id = openstack_networking_subnet_v2.roflsubnet_v6.id
# }

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

# NEW
resource "openstack_networking_network_v2" "roflnet-new" {
  name           = "roflnet-new"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "roflsubnet-new-v4" {
  name       = "better-rofl-subnet-v4"
  network_id = openstack_networking_network_v2.roflnet-new.id
  cidr       = "10.69.44.0/24"
  ip_version = 4
}

resource "openstack_networking_router_v2" "roflrouter-new" {
  name                = "roflrouter-new"
  admin_state_up      = true
  external_network_id = var.provider_network_id
}

resource "openstack_networking_router_interface_v2" "roflrouter-new-interface-v4" {
  router_id = openstack_networking_router_v2.roflrouter-new.id
  subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v4.id
}

# vim: set ft=terraform
