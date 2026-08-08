resource "oci_core_volume_backup_policy" "oci_01_data" {
  compartment_id = var.oci_compartment_id
  display_name   = "oci-01-data-free-tier"

  freeform_tags = {
    managed-by = "tofu"
  }

  schedules {
    backup_type       = "INCREMENTAL"
    period            = "ONE_DAY"
    retention_seconds = 259200
    time_zone         = "REGIONAL_DATA_CENTER_TIME"
  }
}

resource "oci_core_volume_backup_policy_assignment" "oci_01_data" {
  asset_id  = oci_core_volume.oci_01_data.id
  policy_id = oci_core_volume_backup_policy.oci_01_data.id

  lifecycle {
    prevent_destroy = true
  }
}
