resource "oci_core_instance" "oci_04" {
  display_name        = "oci-04"
  availability_domain = "WMjr:EU-FRANKFURT-1-AD-1"
  compartment_id      = var.oci_compartment_id

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_image.ubuntu-2204-minimal-aarch64-202402180.image_id
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.oci_subnet_01.id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

# vim: set ft=terraform :
