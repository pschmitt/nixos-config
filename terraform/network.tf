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

resource "openstack_networking_subnetpool_v2" "customer_ipv6" {
  name             = "customer-ipv6"
  prefixes         = ["2a00:c320:1000::/48"]
  address_scope_id = openstack_networking_addressscope_v2.bgpv6.id
  is_default       = true
  shared           = true
}

resource "openstack_networking_addressscope_v2" "bgpv6" {
  name       = "bgpv6"
  ip_version = 6
  shared     = true
}

resource "openstack_networking_subnet_v2" "roflsubnet_v6" {
  name          = "roflsubnet-v6"
  network_id    = openstack_networking_network_v2.roflnet.id
  subnetpool_id = openstack_networking_subnetpool_v2.customer_ipv6.id
  ip_version    = 6
  # ipv6_address_mode = "slaac" # or dhcpv6-stateful, dhcpv6-stateless
  # ipv6_ra_mode      = "slaac" # or dhcpv6-stateful, dhcpv6-stateless
  ipv6_address_mode = "dhcpv6-stateful"
  ipv6_ra_mode      = "dhcpv6-stateful"
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

# vim: set ft=terraform
