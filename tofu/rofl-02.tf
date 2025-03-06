resource "openstack_blockstorage_volume_v3" "rofl_02_boot_volume" {
  name              = "rofl-02-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (rofl-02)"
  availability_zone = var.availability_zone

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_compute_instance_v2" "rofl-02" {
  name              = "rofl-02"
  flavor_name       = "m1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  availability_zone = var.availability_zone
  # security_groups   = ["default", openstack_networking_secgroup_v2.secgroup_ssh.name]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl_02_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  network {
    port = openstack_networking_port_v2.rofl_02_port.id
  }
}

resource "openstack_networking_port_v2" "rofl_02_port" {
  name           = "rofl-02-port"
  network_id     = openstack_networking_network_v2.roflnet.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet_v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.roflsubnet_v6.id
  # }
}

resource "openstack_networking_port_secgroup_associate_v2" "rofl_02_secgroup_assoc" {
  port_id = openstack_networking_port_v2.rofl_02_port.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id,
    openstack_networking_secgroup_v2.secgroup_email.id,
    openstack_networking_secgroup_v2.secgroup_xmr.id
  ]
}

resource "openstack_networking_floatingip_v2" "rofl_02_fip" {
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl_02_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.rofl_02_fip.address
  port_id     = openstack_networking_port_v2.rofl_02_port.id
}

module "nix-rofl-02" {
  depends_on             = [openstack_compute_instance_v2.rofl-02]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-02.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-02.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_02_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-02.id
  debug_logging          = true
  extra_environment = {
    TARGET_HOST = "rofl-02"
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
