variable "public_ssh_key" {
  description = "Public SSH key for accessing the VM"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOsodZo47l6by834BZ52mEI14gIs7GRxpRRAnocWlA2 pschmitt@x13"
}

resource "openstack_compute_keypair_v2" "keypair" {
  name       = "my_keypair"
  public_key = var.public_ssh_key
}

resource "openstack_blockstorage_volume_v3" "boot_volume" {
  name        = "nixos-anywhere-boot-volume"
  size        = 50 # GB
  image_id    = "Ubuntu 22.04 Jammy Jellyfish - Latest"
  description = "Boot volume for NixOS VM"
}

resource "openstack_compute_instance_v2" "nixos_anywhere_vm" {
  name            = "nixos-anywhere"
  flavor_name     = "m1.small"
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = ["default", "yolo"]

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.boot_volume.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    name = "roflnet"
  }
}

resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool = "provider"
}

resource "openstack_compute_floatingip_associate_v2" "fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  instance_id = openstack_compute_instance_v2.nixos_anywhere_vm.id
}

module "system-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "..#nixosConfigurations.nixos-optimist.config.system.build.toplevel"
}

module "disko" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "..#nixosConfigurations.nixos-optimist.config.system.build.diskoScript"
}

module "install" {
  source            = "github.com/nix-community/nixos-anywhere//terraform/install"
  nixos_system      = module.system-build.result.out
  nixos_partitioner = module.disko.result.out
  target_host       = openstack_networking_floatingip_v2.floating_ip.address
  target_user       = "ubuntu"
}

output "vm_floating_ip" {
  value       = openstack_networking_floatingip_v2.floating_ip.address
  description = "Floating IP address of the deployed NixOS VM"
}
