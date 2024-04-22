resource "oci_core_vcn" "oci_vcn" {
  compartment_id = var.oci_compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "vcn-20221001-0842"
}

resource "oci_core_subnet" "oci_subnet_01" {
  cidr_block                 = "10.0.0.0/24"
  compartment_id             = var.oci_compartment_id
  display_name               = "subnet-20221001-0842"
  dns_label                  = "subnet10010845"
  prohibit_public_ip_on_vnic = false
  vcn_id                     = oci_core_vcn.oci_vcn.id
}
