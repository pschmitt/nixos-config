resource "openstack_blockstorage_volume_v3" "rofl_08_boot_volume" {
  provider          = openstack.optimist-legacy
  name              = "rofl-08-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (rofl-08)"
  availability_zone = openstack_blockstorage_volume_v3.blobarr_volume.availability_zone
}

resource "openstack_compute_instance_v2" "rofl-08" {
  provider          = openstack.optimist-legacy
  name              = "rofl-08"
  flavor_name       = "s1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair_legacy.name
  availability_zone = openstack_blockstorage_volume_v3.blobarr_volume.availability_zone
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_ssh.name,
    openstack_networking_secgroup_v2.secgroup_http.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl_08_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl_08_port.id
  }
}

resource "openstack_networking_port_v2" "rofl_08_port" {
  provider = openstack.optimist-legacy
  name     = "rofl-08-port"
  # network_id     = openstack_networking_network_v2.better_rofl_net.id
  network_id     = openstack_networking_network_v2.roflnet-new.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.roflsubnet_v6.id
  # }
}

resource "openstack_networking_port_secgroup_associate_v2" "rofl_08_secgroup_assoc" {
  provider = openstack.optimist-legacy
  port_id  = openstack_networking_port_v2.rofl_08_port.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id
  ]
}

resource "openstack_networking_floatingip_v2" "rofl_08_fip" {
  provider = openstack.optimist-legacy
  pool     = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl_08_fip_associate" {
  provider    = openstack.optimist-legacy
  floating_ip = openstack_networking_floatingip_v2.rofl_08_fip.address
  port_id     = openstack_networking_port_v2.rofl_08_port.id
}

locals {
  nixos_vars_file_rofl_08 = "../hosts/rofl-08/tf-vars.json"
  nixos_vars_rofl_08 = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.rofl_08_boot_volume.id,
        name = openstack_blockstorage_volume_v3.rofl_08_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.rofl_08_boot_volume.availability_zone
      },
      data = {
        id     = openstack_blockstorage_volume_v3.blobarr_volume.id,
        name   = openstack_blockstorage_volume_v3.blobarr_volume.name,
        az     = openstack_blockstorage_volume_v3.blobarr_volume.availability_zone
        device = openstack_compute_volume_attach_v2.va_blobarr.device # /dev/sdb for example
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.rofl_08_fip.address
    }
  }
}

resource "local_file" "nixos_vars_rofl-08" {
  content         = jsonencode(local.nixos_vars_rofl_08)
  filename        = local.nixos_vars_file_rofl_08
  file_permission = "600"

  # Automatically adds the generated file to Git
  # provisioner "local-exec" {
  #   interpreter = ["sh", "-c"]
  #   command     = "git add -f '${local.nixos_vars_file}'"
  # }
}

module "nix-rofl-08" {
  depends_on = [
    openstack_compute_instance_v2.rofl-08,
    openstack_networking_port_v2.rofl_08_port,
    openstack_networking_router_v2.roflrouter-new,
    openstack_networking_router_interface_v2.roflrouter-new-interface-v4,
    openstack_networking_floatingip_associate_v2.rofl_08_fip_associate,
    cloudflare_record.records["rofl-08.brkn.lol"],
    cloudflare_record.records["*.rofl-08.brkn.lol"],
    local_file.nixos_vars_rofl-08,
  ]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-08.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-08.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_08_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-08.id
  debug_logging          = true
  build_on_remote        = true
  # phases = [
  #   "kexec",
  #   # "disko",
  #   # "install",
  #   # "reboot"
  # ]
  extra_environment = {
    TARGET_HOST = "rofl-08"
  }
  disk_encryption_key_scripts = [
    {
      path   = "/tmp/disk-1.key",
      script = "${path.module}/scripts/decrypt-luks-passphrase.sh"
    },
    {
      path   = "/tmp/disk-2.key",
      script = "${path.module}/scripts/decrypt-luks-passphrase-data.sh"
    }
  ]
  extra_files_script = "${path.module}/scripts/decrypt-ssh-secrets.sh"
}

# vim: set ft=terraform
