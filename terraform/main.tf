
module "system-build" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "..#nixosConfigurations.rofl-02.config.system.build.toplevel"
}

module "disko" {
  source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute = "..#nixosConfigurations.rofl-02.config.system.build.diskoScript"
}

module "install" {
  source            = "github.com/nix-community/nixos-anywhere//terraform/install"
  nixos_system      = module.system-build.result.out
  nixos_partitioner = module.disko.result.out
  target_host       = openstack_networking_floatingip_v2.floating_ip.address
  target_user       = var.nixos_anywhere_ssh_user
  instance_id       = openstack_compute_instance_v2.rofl-02.id
}

# vim: set ft=terraform
