variable "domains" {
  type = map(object({
    dkim_public_key = string
    cloudflare_mx   = bool
  }))

  default = {
    "pschmitt.dev" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz2Yz+Sxm+fvWjnQyTpMRJFUUBBjBYENNWB/+rlQ25J9RJxWwSyIhRJQdcGquXARoKf9WT31KgbxglL4eUcRjWvGRP6Kz9e7bvseT1y4HR4lx0/yCzt4BmzsdX0BBGUL/PvWLFr0p/8hC6KNGzDpHgSAWXS8hF1yIyAe5yMnVzSogJo+cJTc+nmcH8g+j86naXmtRKXxuL8GfM97dpVwflulfUPWMhAoeTUzpUU90t45B0tz7GOCRXM4unIY0ZJDnboXlSX92vFTiVRvzgm5eBE+qUkKBZKHTcNhxZizQGZAULVhGNs3fsP8jl7ni2Pt9fEoGIzmAfQc/FYmVQtYQ5JZhGgk8SjDP8D7KzjR4Eg0kQN+oRuhDLnGrXwyJFc5bWiGt8+a5Fiy2sNAzEn8iIeucan9HFrB1oeLnvIwQMQXXhNsqPQjwmC7/2CNbaENQFFXTmZSsdY0UPkc7jBdgvO3mmokehVtAm3rGJJi/DjNDMp9a42tvvHQHHNcbdmEO3xEUFxfLSGY0dMGlWm0wGzhw6Uu6DjG3Sc5QO3AHY3Q4L4BnEIZZABw+aC1yFKDpTUbeUAhsJirH3NUFOAK4OB4CNiV4RisTAkyt7xN2P4VuAivSUY5tW88Dp76BDuwAJNa5e6O8Gjr0Qi8KeKSr9/v6ee/M5tXq59nfs/nUSgMCAwEAAQ=="
      cloudflare_mx   = false
    },
    "heimat.dev" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa;p=MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxFeSdBleS75MJrFYl9HZ1aR6zOVBvRdhY4PLtCS02Ed9oLenFMHwQ5D4s7Ddq6zTHu0MRFprzJWMYcETsM0MEER5HUDuKPkpqChTLLQTqMJ4/pjleHj/zRr4GNIkJhp8xZNAcsNCDaDlfzzoY1c7euZj8BhYR8oc/0702408SYKgLq2w8fj/jVHaDcLoesYiNXlJdI4pN99lV/pv9usuMkxdwiADZl9N+PfG8Jm/ZFpkhm9qyECDLnp/G4MOr6/BzouP0ACjiYofsH8fUzXFclS3yGVv4Czd8vy4GlEOqTas6FrVtOKxJ6oFn/y0yfkwKeDmtdg76pHHB2aCTFPrajEfQ9jveEcbK7oladtsjJSJYk2Q4KwSXY0wc5icJjUWHbq5Q3rVH+BEqOGYFEJ6KKq75bQ2/SrQgwnbgKIg8uYX/4tl5ltEjYgiprUPNjxLgrQbHL+CWu9+/DMaaELi0PQ42NQc6yd1WxkMxFlKmYo3AcERn+okq6ldlF/DHrKptgrgFJTkcskdxhIro4W7vyP0nm3bZol4maCmIjxBej5ve/M1m/sVTv8w1FKSSlYe2IGGRFgQJ1dOdqehRQ5przXep2Lzn0oZ8a6fT+WfZOjHGD0d7SlXwyizq8JP9gVpDcz2mX51MaUXv+FXLztXqm9Ti6rW8RwcxeyogYrAY1sCAwEAAQ=="
      cloudflare_mx   = false
    },
    "brkn.lol" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzYK3JqwjHHIhk9OxYBE/FHIZxb7SkzZQLMx8XboOtoEAMsNJ99iKJ0mvywtadIt1giywb/q5xaFFqjsByWxA3vBIdqxTXSjNtTqV93qfq8Lw5YTwk7BGXZoVmMblg9aYOJRkF4LhH0uxOURnQz+Lhoj/cz4bnehfHEE/qii1cKXUhW4wTN4HypC22A3IVcNf3z+eTOcu8KPljpKARka7r0gmgPiunLpppafgbSZKtnycIvLdyTu45AD3+aTi836aZsX0vTty9wTl2JyB1buSpiq54IJyma8YSiwphCzBo4PI9OCXlIHTcuRLcU0id99BN6q3A4kE/Q85ks6DPv0dUQIDAQAB"
      cloudflare_mx   = false
    },
    "curl-pipe.sh" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=NONE"
      cloudflare_mx   = true
    },
    "schmi.tt" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=NONE"
      cloudflare_mx   = true
    },
    "ovm5.de" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=NONE"
      cloudflare_mx   = true
    }
    "server-globuli.de" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=NONE"
      cloudflare_mx   = true
    }
    "bergmann-schmitt.de" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=NONE"
      cloudflare_mx   = true
    }
  }
}

data "cloudflare_zone" "zones" {
  for_each = var.domains
  name     = each.key
}

variable "dns_email_comment" {
  description = "Comment to add to all the mail DNS records"
  type        = string
  default     = "mail"
}

variable "dmarc_report_email" {
  description = "Who to send DMARC reports to"
  type        = string
  default     = "dmarc-report@schmitt.co"
}

variable "main_mail_domain" {
  description = "Main mail domain"
  type        = string
  # NOTE we use mail.brkn.lol here since this the only domain we have a reverse
  # DNS entry for
  default = "mail.brkn.lol"
}

resource "cloudflare_email_routing_settings" "cf_mail_routing" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == true
  }
  zone_id = data.cloudflare_zone.zones[each.key].id
  # FIXME Having this set to false raises an error when applying. Let's just not
  # create a resource when cloudflare_mx is false.
  enabled = true
}

resource "cloudflare_record" "mx" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "@"
  type    = "MX"
  ttl     = 3600
  # content    = "mail.${each.key}"
  content  = var.main_mail_domain
  priority = 10
  comment  = var.dns_email_comment
}

resource "cloudflare_record" "mail" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "mail"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "spf" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "@"
  # content   = "v=spf1 a:mail.${each.key} -all"
  content = "v=spf1 a:${var.main_mail_domain} -all"
  ttl     = 3600
  comment = var.dns_email_comment
}

# https://docker-mailserver.github.io/docker-mailserver/latest/config/best-practices/dkim_dmarc_spf/#dmarc
resource "cloudflare_record" "dmarc" {
  # for_each = data.cloudflare_zone.zones
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "_dmarc"
  # Low
  # content   = "v=DMARC1; p=none"

  # Mid
  # content = "v=DMARC1; p=none; sp=none; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:p@schmitt.co; ruf=mailto:p@schmitt.co"

  # Strict
  content = "v=DMARC1; p=quarantine; sp=quarantine; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:${var.dmarc_report_email}; ruf=mailto:${var.dmarc_report_email}"
  ttl     = 3600
  comment = var.dns_email_comment
}

# Allow receiving DMARC reports for other zones/domains
resource "cloudflare_record" "dmarc-report" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }
  zone_id = cloudflare_zone.schmitt_co.id
  type    = "TXT"
  name    = "${each.key}._report._dmarc"
  content = "v=DMARC1;"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "dkim" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "mail._domainkey"
  content = var.domains[each.key].dkim_public_key
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "mailconf" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "@"
  content = "mailconf=https://autoconfig.${each.key}/mail/config-v1.1.xml"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "autoconfig" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "A"
  name    = "autoconfig"
  content = oci_core_instance.oci_01.public_ip
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "autoconfigure" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "A"
  name    = "autoconfigure"
  content = oci_core_instance.oci_01.public_ip
  ttl     = 3600
  comment = var.dns_email_comment
}

# srv records
resource "cloudflare_record" "srv-autodiscover" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_autodiscover._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data {
    priority = 0
    weight   = 0
    port     = 443
    # target   = "mail.${each.key}"
    target = "autoconfig.brkn.lol"
  }
}

resource "cloudflare_record" "srv-imap" { # starttls
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_imap._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data {
    priority = 0
    weight   = 0
    port     = 143
    # target   = "mail.${each.key}"
    target = var.main_mail_domain
  }
}

resource "cloudflare_record" "srv-imaps" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_imaps._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data {
    priority = 0
    weight   = 0
    port     = 993
    # target   = "mail.${each.key}"
    target = var.main_mail_domain
  }
}

# resource "cloudflare_record" "srv-pop3s" {
#   for_each = {
#     for domain, config in var.domains : domain => config if config.cloudflare_mx == false
#   }
#
#   zone_id = data.cloudflare_zone.zones[each.key].id
#   type    = "SRV"
#   name    = "_pop3s._tcp"
#   ttl     = 3600
#   comment = var.dns_email_comment
#
#   data {
#     priority = 0
#     weight   = 0
#     port     = 995
#     # target   = "mail.${each.key}"
#     target  = var.main_mail_domain
#   }
# }

resource "cloudflare_record" "srv-submission" { # starttls
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_submission._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data {
    priority = 0
    weight   = 0
    port     = 587
    # target   = "mail.${each.key}"
    target = var.main_mail_domain
  }
}

resource "cloudflare_record" "srv-submissions" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_submissions._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data {
    priority = 0
    weight   = 0
    port     = 465
    # target   = "mail.${each.key}"
    target = var.main_mail_domain
  }
}

# cnames
resource "cloudflare_record" "cname-smtp" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "CNAME"
  name    = "smtp"
  content = var.main_mail_domain
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_record" "cname-imap" {
  for_each = {
    for domain, config in var.domains : domain => config if config.cloudflare_mx == false
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "CNAME"
  name    = "imap"
  content = var.main_mail_domain
  ttl     = 3600
  comment = var.dns_email_comment
}
