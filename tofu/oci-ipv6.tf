data "oci_core_internet_gateways" "oci_vcn" {
  compartment_id = var.oci_compartment_id
  state          = "AVAILABLE"
  vcn_id         = oci_core_vcn.oci_vcn.id
}

locals {
  oci_internet_gateway_id = one([
    for gateway in data.oci_core_internet_gateways.oci_vcn.gateways : gateway.id
    if gateway.enabled
  ])

  # Keep the OCI firewall aligned with the public listeners on oci-01. The
  # default security list remains attached for the existing IPv4 rules.
  oci_ipv6_public_tcp_ports = [
    22,   # SSH
    25,   # SMTP
    80,   # HTTP
    143,  # IMAP
    443,  # HTTPS
    465,  # SMTPS
    587,  # Submission
    993,  # IMAPS
    4190, # ManageSieve
  ]
}

resource "oci_core_route_table" "oci_public" {
  compartment_id = var.oci_compartment_id
  display_name   = "oci-public-dual-stack"
  vcn_id         = oci_core_vcn.oci_vcn.id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = local.oci_internet_gateway_id
  }

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = local.oci_internet_gateway_id
  }
}

resource "oci_core_security_list" "oci_ipv6" {
  compartment_id = var.oci_compartment_id
  display_name   = "oci-ipv6-public"
  vcn_id         = oci_core_vcn.oci_vcn.id

  dynamic "ingress_security_rules" {
    for_each = local.oci_ipv6_public_tcp_ports

    content {
      description = "IPv6 TCP port ${ingress_security_rules.value}"
      protocol    = "6"
      source      = "::/0"
      source_type = "CIDR_BLOCK"

      tcp_options {
        max = ingress_security_rules.value
        min = ingress_security_rules.value
      }
    }
  }

  ingress_security_rules {
    description = "IPv6 ICMP"
    protocol    = "58"
    source      = "::/0"
    source_type = "CIDR_BLOCK"
  }

  egress_security_rules {
    destination      = "::/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }
}

data "oci_core_vnic_attachments" "oci_01" {
  compartment_id = var.oci_compartment_id
  instance_id    = oci_core_instance.oci_01.id
}

data "oci_core_vnic_attachments" "oci_03" {
  compartment_id = var.oci_compartment_id
  instance_id    = oci_core_instance.oci_03.id
}

resource "oci_core_ipv6" "oci_01" {
  display_name = "oci-01-primary"
  vnic_id = one([
    for attachment in data.oci_core_vnic_attachments.oci_01.vnic_attachments : attachment.vnic_id
    if attachment.nic_index == 0
  ])

  depends_on = [oci_core_subnet.oci_subnet_01]
}

resource "oci_core_ipv6" "oci_03" {
  display_name = "oci-03-primary"
  vnic_id = one([
    for attachment in data.oci_core_vnic_attachments.oci_03.vnic_attachments : attachment.vnic_id
    if attachment.nic_index == 0
  ])

  depends_on = [oci_core_subnet.oci_subnet_01]
}

# vim: set ft=terraform :
