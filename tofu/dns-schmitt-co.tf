resource "cloudflare_record" "schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "www"
  value   = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "cal_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "cal"
  value   = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "drive_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "drive"
  value   = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "mail_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "mail"
  value   = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "sites_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "sites"
  value   = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "schmitt_co_mx_1" {
  zone_id  = cloudflare_zone.schmitt_co.id
  # FIXME shouldn't this be "@"?
  name     = "schmitt.co"
  value    = "aspmx3.googlemail.com"
  type     = "MX"
  priority = 10
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_2" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "aspmx2.googlemail.com"
  type     = "MX"
  priority = 10
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_3" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "alt2.aspmx.l.google.com"
  type     = "MX"
  priority = 5
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_4" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "alt1.aspmx.l.google.com"
  type     = "MX"
  priority = 5
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_5" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "aspmx.l.google.com"
  type     = "MX"
  priority = 1
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_6" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "aspmx5.googlemail.com"
  type     = "MX"
  priority = 10
  proxied  = false
  ttl      = 1799
}

resource "cloudflare_record" "schmitt_co_mx_7" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "schmitt.co"
  value    = "aspmx4.googlemail.com"
  type     = "MX"
  priority = 10
  proxied  = false
  ttl      = 1799
}

# resource "cloudflare_record" "dmarc_report_brkn_lol_txt" {
#   zone_id = cloudflare_zone.schmitt_co.id
#   name    = "brkn.lol._report._dmarc"
#   value   = "v=DMARC1;"
#   type    = "TXT"
#   proxied = false
#   ttl     = 3600
# }

# resource "cloudflare_record" "dmarc_report_heimat_dev_txt" {
#   zone_id = cloudflare_zone.schmitt_co.id
#   name    = "heimat.dev._report._dmarc"
#   value   = "v=DMARC1;"
#   type    = "TXT"
#   proxied = false
#   ttl     = 3600
# }

resource "cloudflare_record" "schmitt_co_keybase_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "_keybase"
  value   = "keybase-site-verification=boXlqI7ZwmmPcnNYS3kgA-rAQ_99IOkvEgU6bHbjTOQ"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}

# resource "cloudflare_record" "dmarc_report_pschmitt_dev_txt" {
#   zone_id = cloudflare_zone.schmitt_co.id
#   name    = "pschmitt.dev._report._dmarc.schmitt.co"
#   value   = "v=DMARC1;"
#   type    = "TXT"
#   proxied = false
#   ttl     = 3600
# }

resource "cloudflare_record" "spf_schmitt_co_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  value   = "v=spf1 include:_spf.google.com ~all"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}

resource "cloudflare_record" "schmitt_co_google_site_verification_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  value   = "google-site-verification=kECtmN9Ek7N1pyS7IwQEkMSD8Y8RknZ2yElqcM_q5LA"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}

resource "cloudflare_record" "dmarc_report_schmi_tt_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmi.tt._report._dmarc"
  value   = "v=DMARC1;"
  type    = "TXT"
  comment = "Allow receiving DMARC reports for schmi.tt"
  proxied = false
  ttl     = 1
}
