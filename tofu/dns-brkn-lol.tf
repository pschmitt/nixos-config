resource "cloudflare_record" "wildcard-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "*"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_record" "gitea-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "gitea"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "healthchecks-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "healthchecks"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "hc-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "hc"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "img-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "img"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_record" "immich-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "immich"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_record" "mmonit-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "mmonit"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_03.public_ip
}

resource "cloudflare_record" "oci-yum-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "oci-yum"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_record" "traefik-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "traefik"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_record" "webmail-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "webmail"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  ttl     = 3600
}

resource "cloudflare_record" "xmr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "xmr"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_record" "x-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "x"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_record" "xp-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "xp"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_record" "cwabd-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "cwabd"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

# jellyfin
resource "cloudflare_record" "media-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "media"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "jelly-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jelly"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "jellyfin-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jellyfin"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "jellyseer-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jellyseer"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "pp-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "pp"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "tv-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "tv"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

# arr
resource "cloudflare_record" "ll-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "ll"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "snr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "snr"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "rdr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "rdr"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "to-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "to"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_record" "tdarr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "tdarr"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}
