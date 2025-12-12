resource "cloudflare_dns_record" "wildcard_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

# CNAME records for google workspace
# NOTE The mail record is provided by dns-email.tf
resource "cloudflare_dns_record" "cal_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "cal"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "drive_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "drive"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "sites_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "sites"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# TXT records for verification
resource "cloudflare_dns_record" "schmitt_co_google_site_verification_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  content = "google-site-verification=kECtmN9Ek7N1pyS7IwQEkMSD8Y8RknZ2yElqcM_q5LA"
  type    = "TXT"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "schmitt_co_keybase_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "_keybase"
  content = "keybase-site-verification=boXlqI7ZwmmPcnNYS3kgA-rAQ_99IOkvEgU6bHbjTOQ"
  type    = "TXT"
  proxied = false
  ttl     = 1
}
