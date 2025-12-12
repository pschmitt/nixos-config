resource "cloudflare_dns_record" "wilcard-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "*"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}
