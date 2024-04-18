terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.44"
    }
  }

  backend "s3" {
    bucket                      = "terraform-state-heimat-dev"
    key                         = "nixos-config.tfstate"
    region                      = "eu-central-2"
    endpoint                    = "s3.eu-central-2.wasabisys.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    # access_key=$AWS_ACCESS_KEY_ID
    # secret_key=$AWS_SECRET_ACCESS_KEY
  }
}

provider "openstack" {
  cloud = "internal-employee-pschmitt"
}

# vim: set ft=terraform
