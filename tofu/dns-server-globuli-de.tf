resource "cloudflare_record" "wildcard_server_globuli_de" {
  zone_id = cloudflare_zone.server_globuli_de.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "server_globuli_de" {
  zone_id = cloudflare_zone.server_globuli_de.id
  name    = "@"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}
