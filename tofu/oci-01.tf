resource "oci_core_instance" "oci_01" {
  display_name        = "oci-01"
  availability_domain = "WMjr:EU-FRANKFURT-1-AD-2"
  compartment_id      = var.oci_compartment_id

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type = "image"
    source_id   = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaaj6g2lci5ed7nfhk46olwkhmwkzrobyo3jntnhkk7fnm2vqflorna"
  }

  # create_vnic_details {
  #   subnet_id = oci_core_subnet.oci_subnet_01.id
  # }

  # metadata = {
  #   ssh_authorized_keys = var.ssh_public_key
  # }
}

# vim: set ft=terraform :
