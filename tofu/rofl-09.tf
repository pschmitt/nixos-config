resource "openstack_blockstorage_volume_v3" "rofl-09_boot_volume" {
  provider    = openstack.optimist-legacy
  name        = "rofl-09-boot-volume"
  size        = 150 # GiB
  image_id    = var.nixos_anywhere_image
  description = "Boot volume for NixOS VM (rofl-09)"
}

resource "openstack_compute_instance_v2" "rofl-09" {
  provider    = openstack.optimist-legacy
  name        = "rofl-09"
  flavor_name = "s1.xlarge"
  key_pair    = openstack_compute_keypair_v2.keypair_legacy.name
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_ssh.name,
    openstack_networking_secgroup_v2.secgroup_http.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl-09_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl-09_port.id
  }
}

resource "openstack_networking_port_v2" "rofl-09_port" {
  provider       = openstack.optimist-legacy
  name           = "rofl-09-port"
  network_id     = openstack_networking_network_v2.roflnet-new.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v6.id
  # }
}

resource "openstack_networking_floatingip_v2" "rofl-09_fip" {
  provider    = openstack.optimist-legacy
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl-09_fip_associate" {
  provider    = openstack.optimist-legacy
  depends_on = [
    openstack_networking_router_interface_v2.roflrouter-new-interface-v4
  ]
  floating_ip = openstack_networking_floatingip_v2.rofl-09_fip.address
  port_id     = openstack_networking_port_v2.rofl-09_port.id
}

locals {
  nixos_vars_file_rofl-09 = "../hosts/rofl-09/tf-vars.json"
  nixos_vars_rofl-09 = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.rofl-09_boot_volume.id,
        name = openstack_blockstorage_volume_v3.rofl-09_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.rofl-09_boot_volume.availability_zone
      },
      data = {
        id     = openstack_blockstorage_volume_v3.rofldata_volume_legacy.id,
        name   = openstack_blockstorage_volume_v3.rofldata_volume_legacy.name,
        az     = openstack_blockstorage_volume_v3.rofldata_volume_legacy.availability_zone
        device = openstack_compute_volume_attach_v2.va_rofldata_legacy.device # /dev/sdb for example
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.rofl-09_fip.address
    }
  }
}

resource "local_file" "nixos_vars_rofl-09" {
  content         = jsonencode(local.nixos_vars_rofl-09)
  filename        = local.nixos_vars_file_rofl-09
  file_permission = "600"

  # Automatically adds the generated file to Git
  # provisioner "local-exec" {
  #   interpreter = ["sh", "-c"]
  #   command     = "git add -f '${local.nixos_vars_file}'"
  # }
}

module "nix-rofl-09" {
  depends_on = [
    openstack_compute_instance_v2.rofl-09,
    openstack_networking_floatingip_associate_v2.rofl-09_fip_associate,
    openstack_compute_volume_attach_v2.va_rofldata_legacy,
    cloudflare_record.records["rofl-09.brkn.lol"],
    cloudflare_record.records["*.rofl-09.brkn.lol"],
    local_file.nixos_vars_rofl-09,
  ]

  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-09.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-09.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl-09_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-09.id
  debug_logging          = true
  build_on_remote        = true

  extra_environment = {
    TARGET_HOST = "rofl-09"
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
