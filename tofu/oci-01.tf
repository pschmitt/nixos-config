resource "oci_core_instance" "oci_01" {
  # FIXME: replace the ephemeral public IPv4 with a reserved OCI public IP
  # before relying on it for permanent DNS/PTR records.
  display_name        = "oci-01"
  availability_domain = "WMjr:EU-FRANKFURT-1-AD-2"
  compartment_id      = var.oci_compartment_id

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  preserve_boot_volume = true

  lifecycle {
    prevent_destroy = true
  }

  source_details {
    source_type = "bootVolume"
    source_id   = "ocid1.bootvolume.oc1.eu-frankfurt-1.abtheljr4kgcs7gb5twgxwcyeulo2vrfvfquf22a4hppfeshg37py67q6gvq"
  }

  # create_vnic_details {
  #   subnet_id = oci_core_subnet.oci_subnet_01.id
  # }

  # metadata = {
  #   ssh_authorized_keys = var.ssh_public_key
  # }
}

module "nix-oci-01" {
  depends_on             = [oci_core_instance.oci_01]
  source                 = "github.com/numtide/nixos-anywhere//terraform/all-in-one"
  nixos_system_attr      = "..#nixosConfigurations.oci-01.config.system.build.toplevel"
  nixos_partitioner_attr = "..#nixosConfigurations.oci-01.config.system.build.diskoScript"
  target_host            = oci_core_instance.oci_01.public_ip
  install_user           = "ubuntu"
  target_user            = "pschmitt"
  install_ssh_key        = file("${path.module}/nixos-anywhere_id_ed25519")
  instance_id            = oci_core_instance.oci_01.id
  debug_logging          = false

  extra_environment = {
    TARGET_HOST = "oci-01"
  }

  disk_encryption_key_scripts = [
    {
      path   = "/tmp/disk-1.key"
      script = "${path.module}/scripts/decrypt-luks-passphrase.sh"
    },
    {
      path   = "/tmp/disk-2.key"
      script = "${path.module}/scripts/decrypt-luks-passphrase-data.sh"
    }
  ]

  extra_files_script = "${path.module}/scripts/decrypt-ssh-secrets.sh"
}

# vim: set ft=terraform :
