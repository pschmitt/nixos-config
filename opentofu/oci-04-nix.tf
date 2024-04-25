module "nix-oci-04" {
  depends_on             = [oci_core_instance.oci_04]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.oci-04.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.oci-04.config.system.build.diskoScript"
  target_host            = oci_core_instance.oci_04.public_ip
  install_user           = var.nixos_anywhere_ssh_user
  instance_id            = oci_core_instance.oci_04.id
  debug_logging          = true
  extra_environment = {
    TARGET_HOST = "oci-04"
    REMOTE_HOST = oci_core_instance.oci_04.public_ip
    REMOTE_USER = var.nixos_anywhere_ssh_user
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
