resource "oci_core_instance" "oci_03" {
  display_name        = "oci-03"
  availability_domain = "WMjr:EU-FRANKFURT-1-AD-1"
  compartment_id      = "ocid1.tenancy.oc1..aaaaaaaaamdd4nyggaaoebwgzv4id5ebhj4ginlxcfk4z26gr3kgmp75oanq"

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa7xlh7c3l2xtrn53n5ezp2thnac3hgjo6biolfxisk3l4igfl3xba"
  }

  create_vnic_details {
    subnet_id = "ocid1.subnet.oc1.eu-frankfurt-1.aaaaaaaa7xnnk577h5pdqvzks7rtcnfvkr4cwxcwoiqyfwrhokpe73pbnpka"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

# vim: set ft=terraform :
