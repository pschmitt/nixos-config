resource "cloudflare_account" "me" {
  name = var.cloudflare_email
  type = "standard"
}

resource "cloudflare_zone" "bergmann_schmitt_de" {
  name = "bergmann-schmitt.de"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "brkn_lol" {
  name = "brkn.lol"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "curl-pipe-sh" {
  name = "curl-pipe.sh"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "pschmitt_dev" {
  name = "pschmitt.dev"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "ovm5_de" {
  name = "ovm5.de"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmitt_co" {
  name = "schmitt.co"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone" "schmi-tt" {
  name = "schmi.tt"
  type = "full"
  account = {
    id = cloudflare_account.me.id
  }
  lifecycle {
    prevent_destroy = true
  }
}
