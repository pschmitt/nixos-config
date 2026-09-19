# Tofu-managed Bitwarden entries mirroring tofu-managed secrets, so the two
# stay in sync instead of being hand-copied.
#
# Scope: every restic-wasabi host in var.restic_repo_passwords, and every
# mail account in var.mail_account_passwords except mail_bw_excluded below.
# The Bitwarden item IDs themselves are not tracked here -- they were only
# needed once, in a (now removed) `import` block, to bind these resources to
# the pre-existing items; the binding itself lives in tofu state from here
# on, same as for any other imported resource.

locals {
  mail_bw_excluded = [
    "admin@brkn.lol", # credential lives in the bitwarden.com account entry's notes, not a mail-style login item
  ]

  # Account/host names aren't secret, only the passwords are -- but
  # for_each rejects a key set derived from a variable that's sensitive as a
  # whole, so pull just the (non-sensitive) keys back out here.
  restic_bw_hosts  = nonsensitive(toset(keys(var.restic_repo_passwords)))
  mail_bw_accounts = nonsensitive(toset([for k in keys(var.mail_account_passwords) : k if !contains(local.mail_bw_excluded, k)]))
}

resource "bitwarden_item_secure_note" "restic_wasabi" {
  for_each = local.restic_bw_hosts

  name = "🍃 restic - wasabi - ${each.key}"

  field {
    name = "RESTIC_REPOSITORY"
    text = "s3:${module.restic_wasabi.bucket_urls[each.key]}"
  }
  field {
    name   = "RESTIC_PASSWORD"
    hidden = var.restic_repo_passwords[each.key]
  }
  field {
    name   = "AWS_ACCESS_KEY_ID"
    hidden = module.restic_wasabi.access_key_ids[each.key]
  }
  field {
    name   = "AWS_SECRET_ACCESS_KEY"
    hidden = module.restic_wasabi.access_key_secrets[each.key]
  }
}

resource "bitwarden_item_login" "mail" {
  for_each = local.mail_bw_accounts

  name     = "email: ${each.key}"
  username = each.key
  password = var.mail_account_passwords[each.key]

  uri {
    value = "https://mail.brkn.lol"
  }

  # A few of these entries carry hand-written notes (e.g. which service uses
  # the account) that we never set here -- don't let tofu wipe them.
  lifecycle {
    ignore_changes = [notes]
  }
}

# vim: set ft=terraform :
