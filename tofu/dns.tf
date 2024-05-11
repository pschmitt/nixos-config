resource "cloudflare_account" "me" {
  name = var.cloudflare_email
}

resource "cloudflare_zone" "brkn_lol" {
  zone       = "brkn.lol"
  plan       = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_zone" "heimat_dev" {
  zone       = "heimat.dev"
  plan       = "free"
  account_id = cloudflare_account.me.id
}

resource "cloudflare_zone" "pschmitt_dev" {
  zone       = "pschmitt.dev"
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

resource "cloudflare_record" "rofl-04" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "rofl-04"
  value   = openstack_networking_floatingip_v2.rofl_04_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "rofl-05" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "rofl-05"
  value   = openstack_networking_floatingip_v2.rofl_05_fip.address
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

# resource "cloudflare_record" "oci-04" {
#   zone_id = cloudflare_zone.heimat_dev.id
#   name    = "oci-04"
#   value   = oci_core_instance.oci_04.public_ip
#   type    = "A"
#   ttl     = 3600
# }

resource "cloudflare_record" "wildcard-oci-03" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.oci-03"
  value   = oci_core_instance.oci_03.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "mail-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "mail"
  # TODO Changeme
  value = "130.61.215.245"
  type  = "A"
  ttl   = 3600
}

resource "cloudflare_record" "wilcard-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "*"
  # TODO Changeme
  value = "130.61.215.245"
  type  = "A"
  ttl   = 3600
}

resource "cloudflare_record" "mail-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "mail"
  # TODO Changeme
  value = "130.61.215.245"
  type  = "A"
  ttl   = 3600
}

resource "cloudflare_record" "r01-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "r01"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "r02-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "r02"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "r03-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "r03"
  value   = openstack_networking_floatingip_v2.rofl_03_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "r04-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "r04"
  value   = openstack_networking_floatingip_v2.rofl_04_fip.address
  type    = "A"
  ttl     = 4600
}

resource "cloudflare_record" "r05-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "r05"
  value   = openstack_networking_floatingip_v2.rofl_05_fip.address
  type    = "A"
  ttl     = 5600
}
