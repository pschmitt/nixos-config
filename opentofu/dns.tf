resource "cloudflare_account" "me" {
  name = var.cloudflare_email
}

resource "cloudflare_zone" "heimat_dev" {
  zone       = "heimat.dev"
  plan       = "free"
  account_id = cloudflare_account.me.id
}
resource "cloudflare_record" "wildcard-rofl-01" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.rofl-01"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-rofl-02" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.rofl-02"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-rofl-03" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.rofl-03"
  value   = openstack_networking_floatingip_v2.rofl_03_fip.address
  type    = "A"
  ttl     = 3600
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


resource "cloudflare_record" "oci-03" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "oci-03"
  value   = oci_core_instance.oci_03.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-oci-03" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.oci-03"
  value   = oci_core_instance.oci_03.public_ip
  type    = "A"
  ttl     = 3600
}
