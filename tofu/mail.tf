# Tofu-managed Stalwart mail accounts (mail.brkn.lol / stalwart.brkn.lol on
# oci-01), keyed by full email address since the same local part exists
# under multiple domains (brkn.lol, heimat.dev, comreset.io, pschmitt.dev --
# heimat.dev/comreset.io/pschmitt.dev are legacy domains, kept as-is).
#
# `password` is intentionally omitted for accounts with no matching entry in
# var.mail_account_passwords (missing Bitwarden "email: x" secret) -- the
# provider treats an unset password as untouched, so importing those never
# resets a live credential we don't actually know.
locals {
  mail_accounts = {
    "admin@brkn.lol"            = { name = "admin", domain = "brkn.lol" }
    "ai@brkn.lol"               = { name = "ai", domain = "brkn.lol" }
    "anika@brkn.lol"            = { name = "anika", domain = "brkn.lol" }
    "apprise@brkn.lol"          = { name = "apprise", domain = "brkn.lol" }
    "authentik@brkn.lol"        = { name = "authentik", domain = "brkn.lol" }
    "authentik@heimat.dev"      = { name = "authentik", domain = "heimat.dev" }
    "books@brkn.lol"            = { name = "books", domain = "brkn.lol" }
    "cctv@brkn.lol"             = { name = "cctv", domain = "brkn.lol" }
    "changes@brkn.lol"          = { name = "changes", domain = "brkn.lol" }
    "cheky@comreset.io"         = { name = "cheky", domain = "comreset.io" }
    "dieppe@brkn.lol"           = { name = "dieppe", domain = "brkn.lol" }
    "fnuc@brkn.lol"             = { name = "fnuc", domain = "brkn.lol" }
    "fnuc@heimat.dev"           = { name = "fnuc", domain = "heimat.dev" }
    "geclat@brkn.lol"           = { name = "geclat", domain = "brkn.lol" }
    "geclat@heimat.dev"         = { name = "geclat", domain = "heimat.dev" }
    "github@brkn.lol"           = { name = "github", domain = "brkn.lol" }
    "github@heimat.dev"         = { name = "github", domain = "heimat.dev" }
    "hass@comreset.io"          = { name = "hass", domain = "comreset.io" }
    "hc@heimat.dev"             = { name = "hc", domain = "heimat.dev" }
    "healthchecks@brkn.lol"     = { name = "healthchecks", domain = "brkn.lol" }
    "healthchecks@comreset.io"  = { name = "healthchecks", domain = "comreset.io" }
    "home-assistant@brkn.lol"   = { name = "home-assistant", domain = "brkn.lol" }
    "home-assistant@heimat.dev" = { name = "home-assistant", domain = "heimat.dev" }
    "img@brkn.lol"              = { name = "img", domain = "brkn.lol" }
    "jellyseerr@brkn.lol"       = { name = "jellyseerr", domain = "brkn.lol" }
    "lrz@brkn.lol"              = { name = "lrz", domain = "brkn.lol" }
    "mmonit@brkn.lol"           = { name = "mmonit", domain = "brkn.lol" }
    "n8n@brkn.lol"              = { name = "n8n", domain = "brkn.lol" }
    "nasteanas@comreset.io"     = { name = "nasteanas", domain = "comreset.io" }
    "nextcloud@brkn.lol"        = { name = "nextcloud", domain = "brkn.lol" }
    "nextcloud@heimat.dev"      = { name = "nextcloud", domain = "heimat.dev" }
    "oci-01@brkn.lol"           = { name = "oci-01", domain = "brkn.lol" }
    "oci-01@heimat.dev"         = { name = "oci-01", domain = "heimat.dev" }
    "oci-02@brkn.lol"           = { name = "oci-02", domain = "brkn.lol" }
    "oci-02@heimat.dev"         = { name = "oci-02", domain = "heimat.dev" }
    "oci-03@brkn.lol"           = { name = "oci-03", domain = "brkn.lol" }
    "oci-03@heimat.dev"         = { name = "oci-03", domain = "heimat.dev" }
    "octopi@comreset.io"        = { name = "octopi", domain = "comreset.io" }
    "p@comreset.io"             = { name = "p", domain = "comreset.io" }
    "p@pschmitt.dev"            = { name = "p", domain = "pschmitt.dev" }
    "proxmox@comreset.io"       = { name = "proxmox", domain = "comreset.io" }
    "rofl-01@brkn.lol"          = { name = "rofl-01", domain = "brkn.lol" }
    "rofl-01@heimat.dev"        = { name = "rofl-01", domain = "heimat.dev" }
    "rofl-02@brkn.lol"          = { name = "rofl-02", domain = "brkn.lol" }
    "rofl-02@heimat.dev"        = { name = "rofl-02", domain = "heimat.dev" }
    "rofl-03@brkn.lol"          = { name = "rofl-03", domain = "brkn.lol" }
    "rofl-03@heimat.dev"        = { name = "rofl-03", domain = "heimat.dev" }
    "rofl-09@brkn.lol"          = { name = "rofl-09", domain = "brkn.lol" }
    "rofl-10@brkn.lol"          = { name = "rofl-10", domain = "brkn.lol" }
    "rofl-11@brkn.lol"          = { name = "rofl-11", domain = "brkn.lol" }
    "rofl-12@brkn.lol"          = { name = "rofl-12", domain = "brkn.lol" }
    "rofl-13@brkn.lol"          = { name = "rofl-13", domain = "brkn.lol" }
    "rofl-14@brkn.lol"          = { name = "rofl-14", domain = "brkn.lol" }
    "sso@brkn.lol"              = { name = "sso", domain = "brkn.lol" }
    "test@brkn.lol"             = { name = "test", domain = "brkn.lol" }
    "turris@brkn.lol"           = { name = "turris", domain = "brkn.lol" }
    "turris@heimat.dev"         = { name = "turris", domain = "heimat.dev" }
    "vaultwarden@brkn.lol"      = { name = "vaultwarden", domain = "brkn.lol" }
    "wallos@brkn.lol"           = { name = "wallos", domain = "brkn.lol" }
    "wish@brkn.lol"             = { name = "wish", domain = "brkn.lol" }
    "wrt1900ac@brkn.lol"        = { name = "wrt1900ac", domain = "brkn.lol" }
    "wrt1900ac@heimat.dev"      = { name = "wrt1900ac", domain = "heimat.dev" }
    "x13@brkn.lol"              = { name = "x13", domain = "brkn.lol" }
    "x13@heimat.dev"            = { name = "x13", domain = "heimat.dev" }
    "zabbix@comreset.io"        = { name = "zabbix", domain = "comreset.io" }
    "zazabbix@comreset.io"      = { name = "zazabbix", domain = "comreset.io" }
  }

  # Import (and the provider's own state refresh) populate domain_id, not the
  # name-based `domain` convenience field -- using `domain` here causes a
  # spurious "forces replacement" diff on every already-existing account, so
  # resolve to domain_id ourselves instead.
  mail_domain_ids = {
    "brkn.lol"     = "b"
    "comreset.io"  = "c"
    "pschmitt.dev" = "d"
    "heimat.dev"   = "e"
  }

  # Every other account is live "User" already -- these two are the only
  # accounts where the live server state differs from that default, per the
  # pre-apply plan review. Getting admin@brkn.lol's role wrong here would
  # downgrade the only Admin account.
  mail_roles = {
    "admin@brkn.lol" = "Admin"
  }

  mail_descriptions = {
    "admin@brkn.lol" = "System administrator"
    "lrz@brkn.lol"   = "lrz (nixos-config)"
  }
}

resource "stalwart_account" "host" {
  for_each = local.mail_accounts

  domain_id   = local.mail_domain_ids[each.value.domain]
  name        = each.value.name
  password    = try(var.mail_account_passwords[each.key], null)
  role        = try(local.mail_roles[each.key], "User")
  description = try(local.mail_descriptions[each.key], null)
}

# Bring every pre-existing account under tofu management.
import {
  for_each = local.mail_accounts
  to       = stalwart_account.host[each.key]
  id       = each.key
}

output "mail_account_addresses" {
  value = { for k, a in stalwart_account.host : k => a.email_address }
}

# vim: set ft=terraform :
