resource "oci_core_vcn" "oci_vcn" {
  compartment_id = var.oci_compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "vcn-20221001-0842"

  # OCI allocates a globally routable /56 to the VCN. IPv6 cannot be
  # disabled again after this is enabled.
  is_ipv6enabled = true
}

resource "oci_core_subnet" "oci_subnet_01" {
  cidr_block     = "10.0.0.0/24"
  compartment_id = var.oci_compartment_id
  display_name   = "subnet-20221001-0842"
  dns_label      = "subnet10010845"
  # The Oracle-assigned VCN /56 only appears in state after the VCN's first
  # IPv6 update. The first apply therefore enables the VCN; the next apply
  # derives and assigns this subnet's /64.
  ipv6cidr_block             = try(cidrsubnet(oci_core_vcn.oci_vcn.ipv6cidr_blocks[0], 8, 0), null)
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.oci_public.id
  security_list_ids = [
    oci_core_vcn.oci_vcn.default_security_list_id,
    oci_core_security_list.oci_ipv6.id,
  ]
  vcn_id = oci_core_vcn.oci_vcn.id
}
