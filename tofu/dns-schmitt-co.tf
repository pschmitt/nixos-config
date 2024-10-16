resource "cloudflare_record" "schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "www"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "cal_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "cal"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "drive_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "drive"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "mail_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "mail"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "sites_schmitt_co" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "sites"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# FIXME We might be able to reduce the amount of MX record to a single one!
# MX Prio 1 -> SMTP.GOOGLE.COM
# https://apps.google.com/supportwidget/articlehome?hl=en&article_url=https%3A%2F%2Fsupport.google.com%2Fa%2Fanswer%2F174125%3Fhl%3Den&assistant_event=welcome&assistant_id=gsuitemxrecords-gixvmm&product_context=174125&product_name=UnuFlow&trigger_context=a

resource "cloudflare_record" "schmitt_co_mx" {
  zone_id  = cloudflare_zone.schmitt_co.id
  name     = "@"
  content  = "smtp.google.com"
  type     = "MX"
  priority = 1
  proxied  = false
  ttl      = 1 # auto
}

# Legacy MX records
# resource "cloudflare_record" "schmitt_co_mx_1" {
#   zone_id = cloudflare_zone.schmitt_co.id
#   # FIXME shouldn't this be "@"?
#   name     = "schmitt.co"
#   content  = "aspmx3.googlemail.com"
#   type     = "MX"
#   priority = 10
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_2" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "aspmx2.googlemail.com"
#   type     = "MX"
#   priority = 10
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_3" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "alt2.aspmx.l.google.com"
#   type     = "MX"
#   priority = 5
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_4" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "alt1.aspmx.l.google.com"
#   type     = "MX"
#   priority = 5
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_5" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "aspmx.l.google.com"
#   type     = "MX"
#   priority = 1
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_6" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "aspmx5.googlemail.com"
#   type     = "MX"
#   priority = 10
#   proxied  = false
#   ttl      = 1799
# }
#
# resource "cloudflare_record" "schmitt_co_mx_7" {
#   zone_id  = cloudflare_zone.schmitt_co.id
#   name     = "schmitt.co"
#   content  = "aspmx4.googlemail.com"
#   type     = "MX"
#   priority = 10
#   proxied  = false
#   ttl      = 1799
# }

resource "cloudflare_record" "schmitt_co_keybase_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "_keybase"
  content = "keybase-site-verification=boXlqI7ZwmmPcnNYS3kgA-rAQ_99IOkvEgU6bHbjTOQ"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}

resource "cloudflare_record" "spf_schmitt_co_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  content = "v=spf1 include:_spf.google.com ~all"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}

resource "cloudflare_record" "schmitt_co_google_site_verification_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co"
  content = "google-site-verification=kECtmN9Ek7N1pyS7IwQEkMSD8Y8RknZ2yElqcM_q5LA"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}
