variable "domains" {
  type = map(object({
    dkim_public_key = optional(string, null)
    mx_provider     = string
    dmarc_policy    = optional(string, null)
  }))

  validation {
    condition     = alltrue([for domain in var.domains : contains(["custom", "google", "cloudflare"], domain.mx_provider)])
    error_message = "The mx_provider must be one of 'custom', 'google', or 'cloudflare'."
  }

  default = {
    "pschmitt.dev" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz2Yz+Sxm+fvWjnQyTpMRJFUUBBjBYENNWB/+rlQ25J9RJxWwSyIhRJQdcGquXARoKf9WT31KgbxglL4eUcRjWvGRP6Kz9e7bvseT1y4HR4lx0/yCzt4BmzsdX0BBGUL/PvWLFr0p/8hC6KNGzDpHgSAWXS8hF1yIyAe5yMnVzSogJo+cJTc+nmcH8g+j86naXmtRKXxuL8GfM97dpVwflulfUPWMhAoeTUzpUU90t45B0tz7GOCRXM4unIY0ZJDnboXlSX92vFTiVRvzgm5eBE+qUkKBZKHTcNhxZizQGZAULVhGNs3fsP8jl7ni2Pt9fEoGIzmAfQc/FYmVQtYQ5JZhGgk8SjDP8D7KzjR4Eg0kQN+oRuhDLnGrXwyJFc5bWiGt8+a5Fiy2sNAzEn8iIeucan9HFrB1oeLnvIwQMQXXhNsqPQjwmC7/2CNbaENQFFXTmZSsdY0UPkc7jBdgvO3mmokehVtAm3rGJJi/DjNDMp9a42tvvHQHHNcbdmEO3xEUFxfLSGY0dMGlWm0wGzhw6Uu6DjG3Sc5QO3AHY3Q4L4BnEIZZABw+aC1yFKDpTUbeUAhsJirH3NUFOAK4OB4CNiV4RisTAkyt7xN2P4VuAivSUY5tW88Dp76BDuwAJNa5e6O8Gjr0Qi8KeKSr9/v6ee/M5tXq59nfs/nUSgMCAwEAAQ=="
      mx_provider     = "custom"
    },
    "brkn.lol" = {
      dkim_public_key = "v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzYK3JqwjHHIhk9OxYBE/FHIZxb7SkzZQLMx8XboOtoEAMsNJ99iKJ0mvywtadIt1giywb/q5xaFFqjsByWxA3vBIdqxTXSjNtTqV93qfq8Lw5YTwk7BGXZoVmMblg9aYOJRkF4LhH0uxOURnQz+Lhoj/cz4bnehfHEE/qii1cKXUhW4wTN4HypC22A3IVcNf3z+eTOcu8KPljpKARka7r0gmgPiunLpppafgbSZKtnycIvLdyTu45AD3+aTi836aZsX0vTty9wTl2JyB1buSpiq54IJyma8YSiwphCzBo4PI9OCXlIHTcuRLcU0id99BN6q3A4kE/Q85ks6DPv0dUQIDAQAB"
      mx_provider     = "custom"
    },
    "curl-pipe.sh" = {
      mx_provider = "cloudflare"
    },
    "schmi.tt" = {
      mx_provider = "cloudflare"
    },
    "ovm5.de" = {
      mx_provider = "cloudflare"
    }
    "bergmann-schmitt.de" = {
      mx_provider = "cloudflare"
    }
    "schmitt.co" = {
      mx_provider = "google"
      # https://admin.google.com/ac/apps/gmail/authenticateemail
      dkim_public_key = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCFfKjXJaCES5Z7YSp5OF+aavonYY4me9FzNZ1XgeQYPDOl9dPP1M7w2X8c9j2jgLPeOU7bs2ZDh+MiYU2OeHYFwl6uIO5BEeqhvQcJRJtfNorUvgfJ4v4Hyk5GbSS8OKs3AyskX4m+ImzVnwzjISVh89yLnTNxOs9sWPhpH3sRpQIDAQAB"
      dmarc_policy    = "mid"
    }
  }
}

data "cloudflare_zone" "zones" {
  for_each = var.domains
  filter = {
    name = each.key
  }
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

locals {
  # dmarc_policy_low = "v=DMARC1; p=none"
  dmarc_policy_mid    = "v=DMARC1; p=none; sp=none; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:${var.dmarc_report_email}; ruf=mailto:${var.dmarc_report_email}"
  dmarc_policy_strict = "v=DMARC1; p=quarantine; sp=quarantine; fo=0; adkim=r; aspf=r; pct=100; rf=afrf; ri=86400; rua=mailto:${var.dmarc_report_email}; ruf=mailto:${var.dmarc_report_email}"
  smtp_google         = "smtp.gmail.com"
  imap_google         = "imap.gmail.com"
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
    for domain, config in var.domains : domain => config if config.mx_provider == "cloudflare"
  }
  zone_id = data.cloudflare_zone.zones[each.key].id
  # FIXME Having this set to false raises an error when applying. Let's just not
  # create a resource when mx_provider is not set to "cloudflare"
}

resource "cloudflare_dns_record" "mx" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "@"
  type    = "MX"
  ttl     = 3600
  # NOTE yes it's smtp.google.com and not smtp.gmail.com!
  # https://support.google.com/a/answer/174125?hl=en
  # to verify: https://workspace.google.com/u/0/verify/confirmation
  content = each.value.mx_provider == "google" ? "smtp.google.com" : var.main_mail_domain
  # TODO Guess we could just use prio=1 for our custom domains as well
  priority = each.value.mx_provider == "google" ? 1 : 10
  comment  = var.dns_email_comment
}

resource "cloudflare_dns_record" "mail" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider == "custom"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "mail"
  content = oci_core_instance.oci_01.public_ip
  type    = "A"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "mail_google" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider == "google"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  name    = "mail"
  content = "ghs.googlehosted.com"
  type    = "CNAME"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "spf" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "@"
  # TODO consider using -all for google domains, which is stricter than ~all
  # https://support.google.com/a/answer/33786?hl=en
  # https://support.google.com/a/answer/10683907?hl=en
  content = each.value.mx_provider == "google" ? "v=spf1 include:_spf.google.com ~all" : "v=spf1 a:${var.main_mail_domain} -all"
  ttl     = 3600
  comment = var.dns_email_comment
}

# https://docker-mailserver.github.io/docker-mailserver/latest/config/best-practices/dkim_dmarc_spf/#dmarc
resource "cloudflare_dns_record" "dmarc" {
  # for_each = data.cloudflare_zone.zones
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "_dmarc"
  content = var.domains[each.key].dmarc_policy == "mid" ? local.dmarc_policy_mid : local.dmarc_policy_strict
  ttl     = 3600
  comment = var.dns_email_comment
}

# Allow receiving DMARC reports for other zones/domains
resource "cloudflare_dns_record" "dmarc-report" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare" && domain != "schmitt.co"
  }
  zone_id = cloudflare_zone.schmitt_co.id
  type    = "TXT"
  name    = "${each.key}._report._dmarc"
  content = "v=DMARC1;"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "dkim" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider == "custom" && config.dkim_public_key != null
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "mail._domainkey"
  content = var.domains[each.key].dkim_public_key
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "dkim_google" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider == "google" && config.dkim_public_key != null
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "${each.key}._domainkey"
  content = var.domains[each.key].dkim_public_key
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "mailconf" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "TXT"
  name    = "@"
  content = "mailconf=https://autoconfig.${each.key}/mail/config-v1.1.xml"
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "autoconfig" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "A"
  name    = "autoconfig"
  content = oci_core_instance.oci_01.public_ip
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "autoconfigure" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "A"
  name    = "autoconfigure"
  content = oci_core_instance.oci_01.public_ip
  ttl     = 3600
  comment = var.dns_email_comment
}

# srv records
resource "cloudflare_dns_record" "srv-autodiscover" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_autodiscover._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data = {
    priority = 0
    weight   = 0
    port     = 443
    target   = "autoconfig.${each.key}"
  }
}

resource "cloudflare_dns_record" "srv-imap" { # starttls
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_imap._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data = {
    priority = 0
    weight   = 0
    port     = 143
    target   = each.value.mx_provider == "google" ? local.imap_google : var.main_mail_domain
  }
}

resource "cloudflare_dns_record" "srv-imaps" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_imaps._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data = {
    priority = 0
    weight   = 0
    port     = 993
    target   = each.value.mx_provider == "google" ? local.imap_google : var.main_mail_domain
  }
}

# resource "cloudflare_dns_record" "srv-pop3s" {
#   for_each = {
#     for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
#   }
#
#   zone_id = data.cloudflare_zone.zones[each.key].id
#   type    = "SRV"
#   name    = "_pop3s._tcp"
#   ttl     = 3600
#   comment = var.dns_email_comment
#
#   data = {
#     priority = 0
#     weight   = 0
#     port     = 995
#     target   = each.value.mx_provider == "google" ? local.pop_google : var.main_mail_domain
#   }
# }

resource "cloudflare_dns_record" "srv-submission" { # starttls
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_submission._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data = {
    priority = 0
    weight   = 0
    port     = 587
    target   = each.value.mx_provider == "google" ? local.smtp_google : var.main_mail_domain
  }
}

resource "cloudflare_dns_record" "srv-submissions" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "SRV"
  name    = "_submissions._tcp"
  ttl     = 3600
  comment = var.dns_email_comment

  data = {
    priority = 0
    weight   = 0
    port     = 465
    target   = each.value.mx_provider == "google" ? local.smtp_google : var.main_mail_domain
  }
}

# cnames
resource "cloudflare_dns_record" "cname-smtp" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "CNAME"
  name    = "smtp"
  content = each.value.mx_provider == "google" ? local.smtp_google : var.main_mail_domain
  ttl     = 3600
  comment = var.dns_email_comment
}

resource "cloudflare_dns_record" "cname-imap" {
  for_each = {
    for domain, config in var.domains : domain => config if config.mx_provider != "cloudflare"
  }

  zone_id = data.cloudflare_zone.zones[each.key].id
  type    = "CNAME"
  name    = "imap"
  content = each.value.mx_provider == "google" ? local.imap_google : var.main_mail_domain
  ttl     = 3600
  comment = var.dns_email_comment
}
