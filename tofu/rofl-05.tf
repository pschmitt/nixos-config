resource "openstack_blockstorage_volume_v3" "rofl_05_boot_volume" {
  name              = "rofl-05-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (rofl-05)"
  availability_zone = var.availability_zone
}

resource "openstack_compute_instance_v2" "rofl-05" {
  name              = "rofl-05"
  flavor_name       = "s1.2xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  availability_zone = var.availability_zone
  security_groups   = [
    "default",
    openstack_networking_secgroup_v2.secgroup_ssh.name,
    openstack_networking_secgroup_v2.secgroup_http.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl_05_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl_05_port.id
  }
}

resource "openstack_networking_port_v2" "rofl_05_port" {
  name = "rofl-05-port"
  # network_id     = openstack_networking_network_v2.roflnet.id
  network_id     = openstack_networking_network_v2.better_rofl_net.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.better_rofl_subnet_v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.roflsubnet_v6.id
  # }
}

resource "openstack_networking_port_secgroup_associate_v2" "rofl_05_secgroup_assoc" {
  port_id = openstack_networking_port_v2.rofl_05_port.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id
  ]
}

resource "openstack_networking_floatingip_v2" "rofl_05_fip" {
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl_05_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.rofl_05_fip.address
  port_id     = openstack_networking_port_v2.rofl_05_port.id
}

module "nix-rofl-05" {
  depends_on = [
    openstack_compute_instance_v2.rofl-05,
    openstack_networking_floatingip_associate_v2.rofl_05_fip_associate
  ]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-05.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-05.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_05_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-05.id
  debug_logging          = true
  extra_environment = {
    TARGET_HOST = "rofl-05"
  }
  disk_encryption_key_scripts = [
    {
      path   = "/tmp/disk-1.key",
      script = "${path.module}/scripts/decrypt-luks-passphrase.sh"
    }
  ]
  extra_files_script = "${path.module}/scripts/decrypt-ssh-secrets.sh"
}

# vim: set ft=terraform
