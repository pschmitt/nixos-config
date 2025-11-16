module "restic_wasabi" {
  source = "./modules/wasabi"
  region = var.wasabi_region
  hosts = [
    # servers
    "rofl-10",
    "rofl-11",
    "rofl-12",

    # laptops
    "ge2",
    "gk4",
    "x13"
  ]
}

output "bucket_urls" {
  value = module.restic_wasabi.bucket_urls
}

output "access_key_ids" {
  value     = module.restic_wasabi.access_key_ids
  sensitive = true
}

output "access_key_secrets" {
  value     = module.restic_wasabi.access_key_secrets
  sensitive = true
}
