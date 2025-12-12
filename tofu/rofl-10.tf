resource "openstack_blockstorage_volume_v3" "rofl-10_boot_volume" {
  provider    = openstack.openstack-wiit
  name        = "rofl-10-boot-volume"
  size        = 150 # GiB
  image_id    = var.nixos_anywhere_image
  description = "Boot volume for NixOS VM (rofl-10)"
}

resource "openstack_compute_instance_v2" "rofl-10" {
  provider    = openstack.openstack-wiit
  name        = "rofl-10"
  flavor_name = "s1.xlarge"
  key_pair    = openstack_compute_keypair_v2.keypair.name
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_http.name,
    openstack_networking_secgroup_v2.secgroup_icmp.name,
    openstack_networking_secgroup_v2.secgroup_ssh.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl-10_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl-10_port.id
  }
}

resource "openstack_compute_volume_attach_v2" "va_rofldata" {
  provider    = openstack.openstack-wiit
  instance_id = openstack_compute_instance_v2.rofl-10.id
  volume_id   = openstack_blockstorage_volume_v3.rofl_data.id
}

resource "openstack_networking_port_v2" "rofl-10_port" {
  provider       = openstack.openstack-wiit
  name           = "rofl-10-port"
  network_id     = openstack_networking_network_v2.rofl_net.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.rofl_subnet-v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.rofl_subnet-v6.id
  # }
}

resource "openstack_networking_floatingip_v2" "rofl-10_fip" {
  provider = openstack.openstack-wiit
  pool     = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl-10_fip_associate" {
  provider = openstack.openstack-wiit
  depends_on = [
    openstack_networking_router_interface_v2.roflrouter-interface-v4
  ]
  floating_ip = openstack_networking_floatingip_v2.rofl-10_fip.address
  port_id     = openstack_networking_port_v2.rofl-10_port.id
}

locals {
  nixos_vars_file_rofl-10 = "../hosts/rofl-10/tf-vars.json"
  nixos_vars_rofl-10 = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.rofl-10_boot_volume.id,
        name = openstack_blockstorage_volume_v3.rofl-10_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.rofl-10_boot_volume.availability_zone
      },
      data = {
        id     = openstack_blockstorage_volume_v3.rofl_data.id,
        name   = openstack_blockstorage_volume_v3.rofl_data.name,
        az     = openstack_blockstorage_volume_v3.rofl_data.availability_zone
        device = openstack_compute_volume_attach_v2.va_rofldata.device # /dev/sdb for example
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.rofl-10_fip.address
    }
  }
}

resource "local_file" "nixos_vars_rofl-10" {
  content         = jsonencode(local.nixos_vars_rofl-10)
  filename        = local.nixos_vars_file_rofl-10
  file_permission = "600"

  # Automatically adds the generated file to Git
  provisioner "local-exec" {
    interpreter = ["sh", "-c"]
    command     = "git add -f '${local.nixos_vars_file_rofl-10}'"
  }
}

module "nix-rofl-10" {
  depends_on = [
    openstack_compute_instance_v2.rofl-10,
    openstack_networking_floatingip_associate_v2.rofl-10_fip_associate,
    cloudflare_dns_record.records["rofl-10.brkn.lol"],
    cloudflare_dns_record.records["*.rofl-10.brkn.lol"],
    local_file.nixos_vars_rofl-10,
  ]

  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-10.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-10.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl-10_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-10.id
  debug_logging          = true
  build_on_remote        = true

  extra_environment = {
    TARGET_HOST = "rofl-10"
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
