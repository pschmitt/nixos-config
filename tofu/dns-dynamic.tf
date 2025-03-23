locals {
  dns_entries = [
    {
      hostname = "oci-01",
      content  = oci_core_instance.oci_01.public_ip
    },
    {
      hostname = "oci-03",
      content  = oci_core_instance.oci_03.public_ip
    },
    {
      hostname = "rofl-02",
      content  = openstack_networking_floatingip_v2.rofl_02_fip.address
    },
    {
      hostname = "rofl-03",
      content  = openstack_networking_floatingip_v2.rofl_03_fip.address
    },
    {
      hostname = "rofl-04",
      content  = openstack_networking_floatingip_v2.rofl_04_fip.address
    },
    {
      hostname = "rofl-05",
      content  = openstack_networking_floatingip_v2.rofl_05_fip.address
    },
    {
      hostname = "rofl-06",
      content  = openstack_networking_floatingip_v2.rofl_06_fip.address
    },
    {
      hostname = "rofl-07",
      content  = openstack_networking_floatingip_v2.rofl_07_fip.address
    }
  ]

  zones = {
    brkn_lol = { name = "brkn.lol", id = cloudflare_zone.brkn_lol.id }
  }

  combined_entries = flatten([
    for zone in local.zones : [
      for dns_entry in local.dns_entries : [
        {
          zone_id   = zone.id
          zone_name = zone.name
          record    = dns_entry.hostname
          content   = dns_entry.content
        },
        {
          zone_id   = zone.id
          zone_name = zone.name
          record    = "*.${dns_entry.hostname}"
          content   = dns_entry.content
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
  content = each.value.content
  type    = "A"
  ttl     = 3600
}

# vim: set ft=terraform :
