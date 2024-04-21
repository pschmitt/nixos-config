resource "openstack_compute_keypair_v2" "keypair" {
  name       = "nixos-anywhere"
  public_key = var.ssh_public_key
}

# vim: set ft=terraform
