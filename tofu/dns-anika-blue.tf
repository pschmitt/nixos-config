resource "cloudflare_record" "wildcard_anika_blue" {
  zone_id = cloudflare_zone.anika_blue.id
  name    = "*"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "anika_blue" {
  zone_id = cloudflare_zone.anika_blue.id
  name    = "@"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  type    = "A"
  proxied = false
  ttl     = 1
}
