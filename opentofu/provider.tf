terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    oci = {
      source  = "oracle/oci"
      version = "5.38.0"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.44"
    }
  }

  backend "s3" {
    # NOTE We cannot use vars here :(
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
  cloud = var.openstack_cloud
}

# vim: set ft=terraform :
