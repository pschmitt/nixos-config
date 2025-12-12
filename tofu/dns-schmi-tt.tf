resource "cloudflare_dns_record" "wildcard_schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  name    = "@"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

# bluesky verification
resource "cloudflare_dns_record" "bluesky-schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  name    = "_atproto.p"
  content = "did=did:plc:xnruav2mf2nhyysfpvpwflbu"
  type    = "TXT"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "dieppe-schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  type    = "A"
  name    = "dieppe"
  content = oci_core_instance.oci_01.public_ip
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "wildcard-dieppe-schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  type    = "A"
  name    = "*.dieppe"
  content = oci_core_instance.oci_01.public_ip
  proxied = false
  ttl     = 1
}
