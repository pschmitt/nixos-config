resource "openstack_compute_keypair_v2" "keypair" {
  name       = "nixos-anywhere"
  public_key = var.public_ssh_key
}

resource "openstack_networking_port_v2" "roflport" {
  name           = "roflport"
  network_id     = openstack_networking_network_v2.roflnet.id
  admin_state_up = "true"
}

resource "openstack_blockstorage_volume_v3" "boot_volume" {
  name        = "nixos-anywhere-boot-volume"
  size        = 150 # GiB
  image_id    = "Ubuntu 22.04 Jammy Jellyfish - Latest"
  description = "Boot volume for NixOS VM"
  availability_zone = var.availability_zone
}

resource "openstack_compute_instance_v2" "nixos_anywhere_vm" {
  name            = "nixos-anywhere"
  flavor_name     = "m1.xlarge"
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = ["default", "yolo"]
  availability_zone = "es1"

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    # uuid = openstack_networking_network_v2.roflnet.id
    port = openstack_networking_port_v2.roflport.id
  }
}

# vim: set ft=terraform
