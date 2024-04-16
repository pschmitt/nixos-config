terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.44"
    }
  }
}

provider "openstack" {
  cloud = "internal-employee-pschmitt"
}

# vim: set ft=terraform
