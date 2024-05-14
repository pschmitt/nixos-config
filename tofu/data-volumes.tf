resource "openstack_blockstorage_volume_v3" "data_volume" {
  name              = "roflvol-02"
  size              = 4096 # GiB
  availability_zone = var.availability_zone
  snapshot_id       = "f54c4fef-77c1-4b6e-8129-9faf66aa6062"

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_compute_volume_attach_v2" "va_data" {
  instance_id = openstack_compute_instance_v2.rofl-02.id
  volume_id   = openstack_blockstorage_volume_v3.data_volume.id
}

resource "oci_core_volume" "oci_01_data" {
  availability_domain = oci_core_instance.oci_01.availability_domain
  compartment_id      = var.oci_compartment_id
  display_name        = "data-01"
  size_in_gbs         = 50

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume" "oci_03_data" {
  availability_domain = oci_core_instance.oci_03.availability_domain
  compartment_id      = var.oci_compartment_id
  display_name        = "oci-03-data"
  size_in_gbs         = 50

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "oci_03_volume_attachment" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.oci_03.id
  volume_id       = oci_core_volume.oci_03_data.id
  device          = "/dev/oracleoci/oraclevdz"
}

# vim: set ft=terraform :
