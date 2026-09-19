# Tofu-managed Bitwarden entries for tofu-managed secrets, so the two stay
# in sync instead of being hand-copied. Scoped to lrz's restic + mail
# entries for now, not a full re-import of every existing "🍃 restic -
# wasabi - *" / "email: *" entry.

resource "bitwarden_item_secure_note" "restic_wasabi_lrz" {
  name = "🍃 restic - wasabi - lrz"

  field {
    name = "RESTIC_REPOSITORY"
    text = "s3:${module.restic_wasabi.bucket_urls["lrz"]}"
  }
  field {
    name   = "RESTIC_PASSWORD"
    hidden = var.restic_repo_passwords["lrz"]
  }
  field {
    name   = "AWS_ACCESS_KEY_ID"
    hidden = module.restic_wasabi.access_key_ids["lrz"]
  }
  field {
    name   = "AWS_SECRET_ACCESS_KEY"
    hidden = module.restic_wasabi.access_key_secrets["lrz"]
  }
}

import {
  to = bitwarden_item_secure_note.restic_wasabi_lrz
  id = "2931e33b-134e-4268-adbd-b4ca00e1db3c"
}

resource "bitwarden_item_login" "mail_lrz" {
  name     = "email: lrz@brkn.lol"
  username = "lrz@brkn.lol"
  password = var.mail_account_passwords["lrz@brkn.lol"]

  uri {
    value = "https://mail.brkn.lol"
  }
}

# vim: set ft=terraform :
