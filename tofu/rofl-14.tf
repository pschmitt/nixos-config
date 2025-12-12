resource "openstack_blockstorage_volume_v3" "rofl-14_boot_volume" {
  provider    = openstack.openstack-wiit
  name        = "rofl-14-boot-volume"
  size        = 150 # GiB
  image_id    = var.nixos_anywhere_image
  description = "Boot volume for NixOS VM (rofl-14)"
}

resource "openstack_compute_instance_v2" "rofl-14" {
  provider    = openstack.openstack-wiit
  name        = "rofl-14"
  flavor_name = "s1.2xlarge"
  key_pair    = openstack_compute_keypair_v2.keypair.name
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_http.name,
    openstack_networking_secgroup_v2.secgroup_icmp.name,
    openstack_networking_secgroup_v2.secgroup_ssh.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.rofl-14_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.rofl-14_port.id
  }
}

resource "openstack_networking_port_v2" "rofl-14_port" {
  provider       = openstack.openstack-wiit
  name           = "rofl-14-port"
  network_id     = openstack_networking_network_v2.rofl_net.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.rofl_subnet-v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.rofl_subnet-v6.id
  # }
}

resource "openstack_networking_floatingip_v2" "rofl-14_fip" {
  provider = openstack.openstack-wiit
  pool     = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "rofl-14_fip_associate" {
  provider = openstack.openstack-wiit
  depends_on = [
    openstack_networking_router_interface_v2.roflrouter-interface-v4
  ]
  floating_ip = openstack_networking_floatingip_v2.rofl-14_fip.address
  port_id     = openstack_networking_port_v2.rofl-14_port.id
}

locals {
  nixos_vars_file_rofl-14 = "../hosts/rofl-14/tf-vars.json"
  nixos_vars_rofl-14 = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.rofl-14_boot_volume.id,
        name = openstack_blockstorage_volume_v3.rofl-14_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.rofl-14_boot_volume.availability_zone
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.rofl-14_fip.address
    }
  }
}

resource "local_file" "nixos_vars_rofl-14" {
  content         = jsonencode(local.nixos_vars_rofl-14)
  filename        = local.nixos_vars_file_rofl-14
  file_permission = "600"

  # Automatically adds the generated file to Git
  provisioner "local-exec" {
    interpreter = ["sh", "-c"]
    command     = "git add -f '${local.nixos_vars_file_rofl-14}'"
  }
}

module "nix-rofl-14" {
  depends_on = [
    openstack_compute_instance_v2.rofl-14,
    openstack_networking_floatingip_associate_v2.rofl-14_fip_associate,
    cloudflare_dns_record.records["rofl-14.brkn.lol"],
    cloudflare_dns_record.records["*.rofl-14.brkn.lol"],
    local_file.nixos_vars_rofl-14,
  ]

  # phases = [
  #   "kexec",
  #   "disko",
  #   "install",
  #   "reboot" # Comment out to DEBUG
  # ]

  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-14.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-14.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl-14_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-14.id
  debug_logging          = true
  build_on_remote        = true

  extra_environment = {
    TARGET_HOST = "rofl-14"
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
