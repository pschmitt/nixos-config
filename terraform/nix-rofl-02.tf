# module "system-build" {
#   source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
#   attribute = "..#nixosConfigurations.rofl-02.config.system.build.toplevel"
# }
#
# module "disko" {
#   source    = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
#   attribute = "..#nixosConfigurations.rofl-02.config.system.build.diskoScript"
# }
#
# module "install" {
#   source            = "github.com/nix-community/nixos-anywhere//terraform/install"
#   nixos_system      = module.system-build.result.out
#   nixos_partitioner = module.disko.result.out
#   target_host       = openstack_networking_floatingip_v2.rofl_02_fip.address
#   target_user       = var.nixos_anywhere_ssh_user
#   instance_id       = openstack_compute_instance_v2.rofl-02.id
#   disk_encryption_key_scripts = [
#     {
#       path   = "/tmp/disk-1.key",
#       script = "${path.module}/scripts/decrypt-luks-passphrase.sh"
#     }
#   ]
#   extra_files_script = "${path.module}/scripts/decrypt-ssh-secrets.sh"
# }

module "deploy" {
  # depends_on             = [local_file.nixos_vars]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-02.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-02.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_02_fip.address
  install_user            = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-02.id
  # extra_files_script     = "${path.module}/decrypt-age-keys.sh"
  # extra_environment = {
  #   SOPS_FILE = var.sops_file
  # }
  debug_logging = true
  disk_encryption_key_scripts = [
    {
      path   = "/tmp/disk-1.key",
      script = "${path.module}/scripts/decrypt-luks-passphrase.sh"
    }
  ]
  extra_files_script = "${path.module}/scripts/decrypt-ssh-secrets.sh"
}

# vim: set ft=terraform
