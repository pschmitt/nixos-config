resource "openstack_blockstorage_volume_v3" "rofl_07_boot_volume" {
  name              = "rofl-07-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (rofl-07)"
  availability_zone = var.availability_zone
}

resource "openstack_compute_instance_v2" "rofl-07" {
  name              = "rofl-07"
  flavor_name       = "s1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  availability_zone = var.availability_zone
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_ssh.name,
    openstack_networking_secgroup_v2.secgroup_http.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl_07_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl_07_port.id
  }
}

resource "openstack_networking_port_v2" "rofl_07_port" {
  name = "rofl-07-port"
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

resource "openstack_networking_port_secgroup_associate_v2" "rofl_07_secgroup_assoc" {
  port_id = openstack_networking_port_v2.rofl_07_port.id
  security_group_ids = [
    openstack_networking_secgroup_v2.secgroup_ssh.id,
    openstack_networking_secgroup_v2.secgroup_http.id
  ]
}

resource "openstack_networking_floatingip_v2" "rofl_07_fip" {
  pool = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl_07_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.rofl_07_fip.address
  port_id     = openstack_networking_port_v2.rofl_07_port.id
}

locals {
  nixos_vars_file = "../hosts/rofl-07/tf-vars.json"
  nixos_vars = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.rofl_07_boot_volume.id,
        name = openstack_blockstorage_volume_v3.rofl_07_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.rofl_07_boot_volume.availability_zone
      },
      data = {
        id   = openstack_blockstorage_volume_v3.blob_volume.id,
        name = openstack_blockstorage_volume_v3.blob_volume.name,
        az   = openstack_blockstorage_volume_v3.blob_volume.availability_zone
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.rofl_07_fip.address
    }
  }
}

resource "local_file" "nixos_vars_rofl-07" {
  content         = jsonencode(local.nixos_vars)
  filename        = local.nixos_vars_file
  file_permission = "600"

  # Automatically adds the generated file to Git
  # provisioner "local-exec" {
  #   interpreter = ["sh", "-c"]
  #   command     = "git add -f '${local.nixos_vars_file}'"
  # }
}

module "nix-rofl-07" {
  depends_on = [
    openstack_compute_instance_v2.rofl-07,
    openstack_networking_floatingip_associate_v2.rofl_07_fip_associate,
    openstack_compute_volume_attach_v2.va_blob,
    cloudflare_record.records["rofl-07.brkn.lol"],
    cloudflare_record.records["*.rofl-07.brkn.lol"],
    local_file.nixos_vars_rofl-07
  ]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-07.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-07.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_07_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-07.id
  debug_logging          = true
  build_on_remote        = true
  # phases = [
  #   "kexec",
  #   # "disko",
  #   # "install",
  #   # "reboot"
  # ]
  extra_environment = {
    TARGET_HOST = "rofl-07"
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
