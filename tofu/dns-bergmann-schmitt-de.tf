resource "cloudflare_dns_record" "wildcard_bergmann_schmitt_de" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "*"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "bergmann_schmitt_de" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "@"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}
