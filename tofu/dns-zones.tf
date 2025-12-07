resource "cloudflare_account" "me" {
  name = var.cloudflare_email
}

resource "cloudflare_zone" "anika_blue" {
  zone       = "anika.blue"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "bergmann_schmitt_de" {
  zone       = "bergmann-schmitt.de"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "brkn_lol" {
  zone       = "brkn.lol"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "curl-pipe-sh" {
  zone       = "curl-pipe.sh"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "poor-tools" {
  zone       = "poor.tools"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "pschmitt_dev" {
  zone       = "pschmitt.dev"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "ovm5_de" {
  zone       = "ovm5.de"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmitt_co" {
  zone       = "schmitt.co"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmi-tt" {
  zone       = "schmi.tt"
  plan       = "free"
  account_id = cloudflare_account.me.id
  lifecycle {
    prevent_destroy = true
  }
}
