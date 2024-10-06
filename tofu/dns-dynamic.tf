locals {
  dns_entries = [
    {
      hostname = "oci-01",
      value    = oci_core_instance.oci_01.public_ip
    },
    {
      hostname = "oci-03",
      value    = oci_core_instance.oci_03.public_ip
    },
    {
      hostname = "rofl-02",
      value    = openstack_networking_floatingip_v2.rofl_02_fip.address
    },
    {
      hostname = "rofl-03",
      value    = openstack_networking_floatingip_v2.rofl_03_fip.address
    },
    {
      hostname = "rofl-04",
      value    = openstack_networking_floatingip_v2.rofl_04_fip.address
    },
    {
      hostname = "rofl-05",
      value    = openstack_networking_floatingip_v2.rofl_05_fip.address
    }
  ]

  zones = {
    heimat_dev = { name = "heimat.dev", id = cloudflare_zone.heimat_dev.id },
    brkn_lol   = { name = "brkn.lol", id = cloudflare_zone.brkn_lol.id }
  }

  combined_entries = flatten([
    for zone in local.zones : [
      for dns_entry in local.dns_entries : [
        {
          zone_id   = zone.id
          zone_name = zone.name
          record    = dns_entry.hostname
          value     = dns_entry.value
        },
        {
          zone_id   = zone.id
          zone_name = zone.name
          record    = "*.${dns_entry.hostname}"
          value     = dns_entry.value
        }
      ]
    ]
  ])
}

resource "cloudflare_record" "records" {
  for_each = {
    for entry in local.combined_entries : "${entry.record}.${entry.zone_name}" => entry
  }
  zone_id = each.value.zone_id
  name    = each.value.record
  value   = each.value.value
  type    = "A"
  ttl     = 3600
}

# vim: set ft=terraform :
