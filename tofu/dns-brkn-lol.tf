resource "cloudflare_dns_record" "wildcard-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "*"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_dns_record" "gitea-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "gitea"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_dns_record" "healthchecks-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "healthchecks"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_dns_record" "hc-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "hc"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_dns_record" "img-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "img"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_dns_record" "immich-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "immich"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
}

resource "cloudflare_dns_record" "mmonit-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "mmonit"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_03.public_ip
}

resource "cloudflare_dns_record" "mm-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "mm"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_03.public_ip
}

resource "cloudflare_dns_record" "oci-yum-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "oci-yum"
  type    = "A"
  ttl     = 3600
  content = oci_core_instance.oci_01.public_ip
}

resource "cloudflare_dns_record" "traefik-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "traefik"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
}

resource "cloudflare_dns_record" "webmail-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "webmail"
  content = openstack_networking_floatingip_v2.rofl-10_fip.address
  ttl     = 3600
}

resource "cloudflare_dns_record" "xmr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "xmr"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_dns_record" "x-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "x"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_dns_record" "xp-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  type    = "A"
  name    = "xp"
  content = openstack_networking_floatingip_v2.rofl-12_fip.address
  ttl     = 3600
}

resource "cloudflare_dns_record" "cwabd-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "cwabd"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

# jellyfin
resource "cloudflare_dns_record" "media-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "media"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "jelly-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jelly"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "jellyfin-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jellyfin"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "jellyseer-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "jellyseer"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "pp-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "pp"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "tv-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "tv"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

# arr
resource "cloudflare_dns_record" "ll-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "ll"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "snr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "snr"
  type    = "CNAME"
  ttl     = 3600
  content = "son.arr.brkn.lol"
}

resource "cloudflare_dns_record" "rdr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "rdr"
  type    = "CNAME"
  ttl     = 3600
  content = "rad.arr.brkn.lol"
}

resource "cloudflare_dns_record" "to-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "to"
  type    = "CNAME"
  ttl     = 3600
  content = "to.arr.brkn.lol"
}

resource "cloudflare_dns_record" "tdarr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "tdarr"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}

resource "cloudflare_dns_record" "wildcard-arr-brkn-lol" {
  zone_id = cloudflare_zone.brkn_lol.id
  name    = "*.arr"
  type    = "A"
  ttl     = 3600
  content = openstack_networking_floatingip_v2.rofl-11_fip.address
}
