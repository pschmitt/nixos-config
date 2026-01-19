# resource "openstack_networking_addressscope_v2" "bgpv6" {
#   provider   = openstack.openstack-wiit
#   name       = "bgpv6"
#   ip_version = 6
#   shared     = true
# }
#
# resource "openstack_networking_subnetpool_v2" "customer_ipv6" {
#   provider         = openstack.openstack-wiit
#   name             = "customer-ipv6"
#   prefixes         = ["2a00:c320:1000::/48"]
#   address_scope_id = openstack_networking_addressscope_v2.bgpv6.id
#   is_default       = true
#   shared           = true
# }

# vim: set ft=terraform
