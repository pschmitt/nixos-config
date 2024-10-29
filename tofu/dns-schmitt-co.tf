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

resource "cloudflare_record" "schmitt_co_dkim" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "schmitt.co._domainkey"
  content = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCFfKjXJaCES5Z7YSp5OF+aavonYY4me9FzNZ1XgeQYPDOl9dPP1M7w2X8c9j2jgLPeOU7bs2ZDh+MiYU2OeHYFwl6uIO5BEeqhvQcJRJtfNorUvgfJ4v4Hyk5GbSS8OKs3AyskX4m+ImzVnwzjISVh89yLnTNxOs9sWPhpH3sRpQIDAQAB"
  type    = "TXT"
  proxied = false
  ttl     = 1
}
resource "cloudflare_record" "schmitt_co_dmarc" {
  zone_id = cloudflare_zone.schmitt_co.id
  type    = "TXT"
  name    = "_dmarc"
  # Low
  # content   = "v=DMARC1; p=none"

  # Mid
  content = "v=DMARC1; p=none; sp=none; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:p@schmitt.co; ruf=mailto:p@schmitt.co"

  # Strict
  # content = "v=DMARC1; p=quarantine; sp=quarantine; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:${var.dmarc_report_email}; ruf=mailto:${var.dmarc_report_email}"
  ttl     = 3600
  comment = var.dns_email_comment
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

resource "cloudflare_record" "schmitt_co_keybase_txt" {
  zone_id = cloudflare_zone.schmitt_co.id
  name    = "_keybase"
  content = "keybase-site-verification=boXlqI7ZwmmPcnNYS3kgA-rAQ_99IOkvEgU6bHbjTOQ"
  type    = "TXT"
  proxied = false
  ttl     = 1799
}
