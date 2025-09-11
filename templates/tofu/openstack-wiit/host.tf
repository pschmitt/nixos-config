resource "openstack_blockstorage_volume_v3" "${REPLACEME}_boot_volume" {
  provider          = openstack.openstack-wiit
  name              = "${REPLACEME}-boot-volume"
  size              = 150 # GiB
  image_id          = var.nixos_anywhere_image
  description       = "Boot volume for NixOS VM (${REPLACEME})"
}

resource "openstack_compute_instance_v2" "${REPLACEME}" {
  provider          = openstack.openstack-wiit
  name              = "${REPLACEME}"
  flavor_name       = "s1.xlarge"
  key_pair          = openstack_compute_keypair_v2.keypair.name
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.secgroup_ssh.name,
    openstack_networking_secgroup_v2.secgroup_http.name
  ]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.${REPLACEME}_boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.${REPLACEME}_port.id
  }
}

resource "openstack_networking_port_v2" "${REPLACEME}_port" {
  provider       = openstack.openstack-wiit
  name           = "${REPLACEME}-port"
  network_id     = openstack_networking_network_v2.roflnet-new.id
  admin_state_up = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v4.id
  }

  # fixed_ip {
  #   subnet_id = openstack_networking_subnet_v2.roflsubnet-new-v6.id
  # }
}

resource "openstack_networking_floatingip_v2" "${REPLACEME}_fip" {
  provider = openstack.openstack-wiit
  pool     = "provider"
}

resource "openstack_networking_floatingip_associate_v2" "${REPLACEME}_fip_associate" {
  provider   = openstack.openstack-wiit
  depends_on = [
    openstack_networking_router_interface_v2.roflrouter-new-interface-v4
  ]
  floating_ip = openstack_networking_floatingip_v2.${REPLACEME}_fip.address
  port_id     = openstack_networking_port_v2.${REPLACEME}_port.id
}

locals {
  nixos_vars_file_${REPLACEME} = "../hosts/${REPLACEME}/tf-vars.json"
  nixos_vars_${REPLACEME} = {
    disks = {
      root = {
        id   = openstack_blockstorage_volume_v3.${REPLACEME}_boot_volume.id,
        name = openstack_blockstorage_volume_v3.${REPLACEME}_boot_volume.name,
        az   = openstack_blockstorage_volume_v3.${REPLACEME}_boot_volume.availability_zone
      }
    }
    network = {
      floating_ip = openstack_networking_floatingip_v2.${REPLACEME}_fip.address
    }
  }
}

resource "local_file" "nixos_vars_${REPLACEME}" {
  content         = jsonencode(local.nixos_vars_${REPLACEME})
  filename        = local.nixos_vars_file_${REPLACEME}
  file_permission = "600"

  # Automatically adds the generated file to Git
  provisioner "local-exec" {
    interpreter = ["sh", "-c"]
    command     = "git add -f '${local.nixos_vars_${REPLACEME}}'"
  }
}

module "nix-${REPLACEME}" {
  depends_on = [
    openstack_compute_instance_v2.${REPLACEME},
    openstack_networking_floatingip_associate_v2.${REPLACEME}_fip_associate,
    cloudflare_record.records["${REPLACEME}.brkn.lol"],
    cloudflare_record.records["*.${REPLACEME}.brkn.lol"],
    local_file.nixos_vars_${REPLACEME},
  ]

  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.${REPLACEME}.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.${REPLACEME}.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.${REPLACEME}_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.${REPLACEME}.id
  debug_logging          = true
  build_on_remote        = true

  extra_environment = {
    TARGET_HOST = "${REPLACEME}"
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
