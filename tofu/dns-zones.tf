resource "cloudflare_account" "me" {
  name = var.cloudflare_email
}

resource "cloudflare_zone" "anika_blue" {
  name = "anika.blue"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "bergmann_schmitt_de" {
  name = "bergmann-schmitt.de"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "brkn_lol" {
  name = "brkn.lol"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "curl-pipe-sh" {
  name = "curl-pipe.sh"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "poor-tools" {
  name = "poor.tools"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "pschmitt_dev" {
  name = "pschmitt.dev"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "ovm5_de" {
  name = "ovm5.de"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmitt_co" {
  name = "schmitt.co"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmi-tt" {
  name = "schmi.tt"
  # plan = "free"
  account = { id = cloudflare_account.me.id }
  lifecycle {
    prevent_destroy = true
  }
}
