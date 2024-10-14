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

resource "cloudflare_record" "wildcard-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "rofl-01-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "rofl-01"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-rofl-01-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "*.rofl-01"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
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

resource "cloudflare_record" "gitea-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "git"
  type    = "CNAME"
  ttl     = 3600
  value   = "git.brkn.lol"
}

resource "cloudflare_record" "gitea-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "git"
  type    = "A"
  ttl     = 3600
  value   = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "mmonit-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "mmonit"
  type    = "CNAME"
  ttl     = 3600
  value   = "mmonit.brkn.lol"
}

resource "cloudflare_record" "mmonit-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "mmonit"
  type    = "A"
  ttl     = 3600
  value   = oci_core_instance.oci_03.public_ip
}

resource "cloudflare_record" "hc-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "hc"
  type    = "A"
  ttl     = 3600
  value   = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "healthchecks-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "healthchecks"
  type    = "A"
  ttl     = 3600
  value   = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "immich-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "immich"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "immich-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "immich"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "img-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "img"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "img-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "img"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "media-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "media"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "media-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "media"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "jelly-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "jelly"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "jelly-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jelly"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "jellyfin-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "jellyfin"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "jellyfin-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jellyfin"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "tv-heimat-dev" {
  zone_id = cloudflare_zone.heimat_dev.id
  name    = "tv"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "tv-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "tv"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "traefik-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "traefik"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wilcard-pschmitt-dev" {
  zone_id = cloudflare_zone.pschmitt_dev.id
  name    = "*"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "wildcard-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "*"
  type    = "A"
  ttl     = 3600
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
}

resource "cloudflare_record" "webmail-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "webmail"
  value   = openstack_networking_floatingip_v2.rofl_02_fip.address
  ttl     = 3600
}

