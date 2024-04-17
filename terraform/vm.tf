resource "openstack_compute_keypair_v2" "keypair" {
  name       = "nixos-anywhere"
  public_key = var.public_ssh_key
}

resource "openstack_blockstorage_volume_v3" "boot_volume" {
  name              = "nixos-anywhere-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM"
  availability_zone = var.availability_zone
}

resource "openstack_compute_instance_v2" "rofl-02" {
  name              = "rofl-02"
  flavor_name       = "m1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  availability_zone = var.availability_zone
  # security_groups   = ["default", openstack_networking_secgroup_v2.secgroup_ssh.name]

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

resource "openstack_networking_port_secgroup_associate_v2" "secgroup_assoc" {
  port_id = openstack_networking_port_v2.roflport.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id
  ]
}

# vim: set ft=terraform
