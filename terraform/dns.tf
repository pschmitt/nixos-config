resource "cloudflare_account" "me" {
  name = "philipp@schmitt.co"
}

resource "cloudflare_zone" "heimat_dev" {
  zone = "heimat.dev"
  plan = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_record" "rofl-02" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "rofl-02"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "rofl-03" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "rofl-03"
  value   = openstack_networking_floatingip_v2.rofl_03_fip.address
  type    = "A"
  ttl     = 3600
}
