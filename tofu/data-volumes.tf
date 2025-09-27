resource "openstack_blockstorage_volume_v3" "rofldata_volume_legacy" {
  provider             = openstack.optimist-legacy
  name                 = "rofldata"
  size                 = 4096 # GiB
  availability_zone    = "ix1"
  enable_online_resize = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_blockstorage_volume_v3" "blobarr_volume_legacy" {
  provider             = openstack.optimist-legacy
  name                 = "blobarr-vol"
  size                 = 4096 # GiB
  availability_zone    = "ix1"
  enable_online_resize = true
  description          = "data volume, arrr!"

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_blockstorage_volume_v3" "rofl_data" {
  provider             = openstack.openstack-wiit
  name                 = "rofl-data"
  size                 = 4096 # GiB
  enable_online_resize = true
  description          = "rofl data"
  availability_zone    = var.availability_zone

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_blockstorage_volume_v3" "blobarr" {
  provider             = openstack.openstack-wiit
  name                 = "blobarr"
  size                 = 4096 # GiB
  enable_online_resize = true
  description          = "data volume, arrr!"
  availability_zone    = var.availability_zone

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_compute_volume_attach_v2" "va_blobarr_legacy" {
  provider    = openstack.optimist-legacy
  instance_id = openstack_compute_instance_v2.rofl-08.id
  volume_id   = openstack_blockstorage_volume_v3.blobarr_volume_legacy.id
}

resource "oci_core_volume" "oci_01_data" {
  availability_domain = oci_core_instance.oci_01.availability_domain
  compartment_id      = var.oci_compartment_id
  display_name        = "oci-01-data"
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

resource "oci_core_volume_attachment" "oci_01_volume_attachment" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.oci_01.id
  volume_id       = oci_core_volume.oci_01_data.id

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
