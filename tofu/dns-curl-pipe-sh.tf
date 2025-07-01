resource "cloudflare_dns_record" "wildcard_curl-pipe-sh" {
  zone_id = cloudflare_zone.curl-pipe-sh.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "curl-pipe-sh" {
  zone_id = cloudflare_zone.curl-pipe-sh.id
  name    = "@"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = false
  ttl     = 1
}
