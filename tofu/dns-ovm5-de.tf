resource "cloudflare_dns_record" "wildcard_ovm5_de" {
  zone_id = cloudflare_zone.ovm5_de.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "ovm5_de" {
  zone_id = cloudflare_zone.ovm5_de.id
  name    = "@"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "hass_ovm5_de" {
  zone_id = cloudflare_zone.ovm5_de.id
  name    = "hass"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}
