module "nix-rofl-04" {
  depends_on             = [openstack_compute_instance_v2.rofl-04]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.rofl-04.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.rofl-04.config.system.build.diskoScript"
  target_host            = openstack_networking_floatingip_v2.rofl_04_fip.address
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = openstack_compute_instance_v2.rofl-04.id
  debug_logging          = true
  extra_environment = {
    TARGET_HOST = "rofl-04"
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
