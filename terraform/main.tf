
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
  instance_id       = openstack_compute_instance_v2.nixos_anywhere_vm.id
}

# vim: set ft=terraform
