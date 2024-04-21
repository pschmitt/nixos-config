module "nix-oci-03" {
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.oci-03.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.oci-03.config.system.build.diskoScript"
  target_host            = "130.61.46.132"
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = "130.61.46.132"
  extra_environment = {
    TARGET_HOST = "oci-03"
  }
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
