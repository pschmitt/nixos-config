terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }

    oci = {
      source  = "oracle/oci"
      version = "~> 7.7.0"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.2.0"
    }

    wasabi = {
      source  = "thesisedu/wasabi"
      version = "~> 4.1"
    }

    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    # NOTE We cannot use vars here :(
    bucket                      = "tofu-state-brkn-lol"
    key                         = "nixos-config.tfstate"
    region                      = "eu-central-2"
    endpoint                    = "s3.eu-central-2.wasabisys.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    # access_key=$AWS_ACCESS_KEY_ID
    # secret_key=$AWS_SECRET_ACCESS_KEY
  }
}

provider "cloudflare" {
  # See terraform.tfvars.sops.json
  email   = var.cloudflare_email
  api_key = var.cloudflare_api_key
}

provider "oci" {
  # See terraform.tfvars.sops.json
  region           = var.oci_region
  tenancy_ocid     = var.oci_tenancy_ocid
  user_ocid        = var.oci_user_ocid
  fingerprint      = var.oci_fingerprint
  private_key_path = var.oci_private_key_path
}

provider "openstack" {
  alias = "openstack-wiit"
  cloud = var.openstack_cloud
}

provider "wasabi" {
  region     = var.wasabi_region
  access_key = var.wasabi_access_key
  secret_key = var.wasabi_secret_key
}

provider "healthchecksio" {
  api_key = var.healthchecksio_api_key

  # Default to the self-hosted instance but allow override through variables.
  api_url = var.healthchecksio_api_url
}
# vim: set ft=terraform :
