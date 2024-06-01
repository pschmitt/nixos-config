resource "cloudflare_account" "me" {
  name = var.cloudflare_email
}

resource "cloudflare_zone" "brkn_lol" {
  zone       = "brkn.lol"
  plan       = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_zone" "heimat_dev" {
  zone       = "heimat.dev"
  plan       = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_zone" "pschmitt_dev" {
  zone       = "pschmitt.dev"
  plan       = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_record" "wildcard-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

# resource "cloudflare_record" "oci-04" {
#   zone_id = cloudflare_zone.heimat_dev.id
#   name    = "oci-04"
#   value   = oci_core_instance.oci_04.public_ip
#   type    = "A"
#   ttl     = 3600
# }

resource "cloudflare_record" "mail-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "mail"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wilcard-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "*"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "mail-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "mail"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "*"
  type    = "A"
  ttl     = 3600
  value   = oci_core_instance.oci_01.public_ip
}
