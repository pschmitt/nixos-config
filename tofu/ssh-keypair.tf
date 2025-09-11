resource "openstack_compute_keypair_v2" "keypair_legacy" {
  provider   = openstack.optimist-legacy
  name       = "nixos-anywhere"
  public_key = var.ssh_public_key
}

resource "openstack_compute_keypair_v2" "keypair" {
  provider   = openstack.openstack-wiit
  name       = "nixos-anywhere"
  public_key = var.ssh_public_key
}

# vim: set ft=terraform
