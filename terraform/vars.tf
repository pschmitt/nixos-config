# FIXME We can't use vars in the provider.backend block
# variable "s3_bucket" {
#   description = "S3 bucket name"
#   type        = string
# }
#
# variable "s3_key" {
#   description = "S3 key"
#   type        = string
# }
#
# variable "s3_region" {
#   description = "S3 region"
#   type        = string
# }
#
# variable "s3_endpoint" {
#   description = "S3 endpoint"
#   type        = string
# }

variable "cloudflare_email" {
  description = "Cloudflare email (CLOUDFLARE_EMAIL)"
  type        = string
}

variable "cloudflare_api_key" {
  description = "Cloudflare API key (CLOUDFLARE_API_KEY)"
  type        = string
}

variable "openstack_cloud" {
  description = "Openstack cloud name (OS_CLOUD)"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for the VM"
  type        = string
  default     = "es1"
}

variable "provider_network_id" {
  description = "Network ID of the provider network"
  type        = string
  default     = "54258498-a513-47da-9369-1a644e4be692"
}

variable "ssh_public_key" {
  description = "Public SSH key for accessing the VM"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvVATHmFG1p5JqPkM2lE7wxCO2JGX3N5h9DEN3T2fKM nixos-anywhere"
}

variable "nixos_anywhere_ssh_user" {
  description = "SSH user for nixos-anywhere"
  type        = string
  default     = "ubuntu"
}

variable "nixos_anywhere_image" {
  description = "Base image to use for provisionning the VM"
  type        = string
  default     = "Ubuntu 22.04 Jammy Jellyfish - Latest"
}

variable "oci_region" {
  description = "OCI region to use"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "oci_compartment_ocid" {
  description = "OCI compartment OCID"
  type        = string
}

variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCI user OCID"
  type        = string
}

variable "oci_fingerprint" {
  description = "OCI user fingerprint"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to the OCI private key"
  type        = string
}

# vim: set ft=terraform
