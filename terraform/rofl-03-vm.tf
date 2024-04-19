resource "openstack_blockstorage_volume_v3" "rofl_03_boot_volume" {
  name              = "rofl-03-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (rofl-03)"
  availability_zone = var.availability_zone
}

resource "openstack_compute_instance_v2" "rofl-03" {
  name              = "rofl-03"
  flavor_name       = "m1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  availability_zone = var.availability_zone
  # security_groups   = ["default", openstack_networking_secgroup_v2.secgroup_ssh.name]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl_03_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  network {
    port = openstack_networking_port_v2.rofl_03_port.id
  }
}

resource "openstack_networking_port_v2" "rofl_03_port" {
  name           = "roflport"
  network_id     = openstack_networking_network_v2.roflnet.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet_v4.id
  }

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet_v6.id
  }
}

resource "openstack_networking_port_secgroup_associate_v2" "rofl_03_secgroup_assoc" {
  port_id = openstack_networking_port_v2.rofl_03_port.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id
  ]
}

resource "openstack_networking_floatingip_v2" "rofl_03_fip" {
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl_03_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.rofl_03_fip.address
  port_id     = openstack_networking_port_v2.rofl_03_port.id
}

# vim: set ft=terraform
