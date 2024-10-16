resource "cloudflare_record" "bergmann_schmitt_de_mx1" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "bergmann-schmitt.de"
  value   = "mx.zoho.com"
  type    = "MX"
  priority = 10
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "bergmann_schmitt_de_mx2" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "bergmann-schmitt.de"
  value   = "mx2.zoho.com"
  type    = "MX"
  priority = 20
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "bergmann_schmitt_de_mx3" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "bergmann-schmitt.de"
  value   = "mx3.zoho.com"
  type    = "MX"
  priority = 50
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "bergmann_schmitt_de_spf" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "bergmann-schmitt.de"
  value   = "v=spf1 include:zoho.com ~all"
  type    = "TXT"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "bergmann_schmitt_de_zoho_verification" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "bergmann-schmitt.de"
  value   = "zoho-verification=zb83290461.zmverify.zoho.com"
  type    = "TXT"
  proxied = false
  ttl     = 1
}

resource "cloudflare_record" "bergmann_schmitt_de_dkim" {
  zone_id = cloudflare_zone.bergmann_schmitt_de.id
  name    = "zmail._domainkey.bergmann-schmitt.de"
  value   = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCeRQJ2jB2YF0d6o28fYPIXVgfg+IEbBXJAV2Pgp9HFQqsuuy0Owh3EAgBz9l9GLa312kDohBSqP/x7EAB1om2e1MuEe7E+s31u6zPk/UfagbviDyQ6ICFyFd522HMuNjrjbVkGjwwrMAPtfbRQDwxi2ZlLUdTAA9OHCPZNVEIe5wIDAQAB"
  type    = "TXT"
  proxied = false
  ttl     = 1
}
