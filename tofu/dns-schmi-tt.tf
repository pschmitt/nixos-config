resource "cloudflare_record" "wildcard_schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "schmi-tt" {
  zone_id = cloudflare_zone.schmi-tt.id
  name    = "@"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}
