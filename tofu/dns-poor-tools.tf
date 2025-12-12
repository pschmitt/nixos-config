resource "cloudflare_dns_record" "wildcard_poor-tools" {
  zone_id = cloudflare_zone.poor-tools.id
  name    = "*"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "poor-tools" {
  zone_id = cloudflare_zone.poor-tools.id
  name    = "@"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}
