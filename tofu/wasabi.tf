module "restic_wasabi" {
  source = "./modules/wasabi"
  hosts  = ["rofl-10", "rofl-11", "rofl-12", "rofl-13", "rofl-14"]

  bucket_prefix       = "restic-backup"
  versioning_enabled  = false
  restic_group_name   = "restic"
  static_group_members = [
    "autorestic",
    "restic-fnuc",
    "restic-ge2",
    "restic-oci-01",
    "restic-oci-03",
    "restic-rofl-03",
    "restic-rofl-08",
    "restic-rofl-09",
    "restic-turris",
    "restic-wrt1900ac",
    "restic-x13",
  ]
}

output "access_key_ids" {
  value     = module.restic_wasabi.access_key_ids
  sensitive = true
}

output "access_key_secrets" {
  value     = module.restic_wasabi.access_key_secrets
  sensitive = true
}
