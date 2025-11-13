module "restic_wasabi" {
  source = "./modules/wasabi"
  hosts = [
    # servers
    "rofl-10", "rofl-11", "rofl-12",
    # laptops
    "gk4"
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
