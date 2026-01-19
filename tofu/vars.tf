# FIXME We can't use vars in the provider.backend block
# The s3_xxx vars are kinda useless for now.
variable "s3_bucket" {
  description = "S3 bucket name"
  type        = string
}

variable "s3_key" {
  description = "S3 key"
  type        = string
  default     = "terraform.tfstate"
}

variable "s3_access_key_id" {
  description = "S3 key"
  type        = string
}

variable "s3_secret_access_key" {
  description = "S3 key"
  type        = string
}

variable "s3_region" {
  description = "S3 region"
  type        = string
}

variable "s3_endpoint" {
  description = "S3 endpoint"
  type        = string
}

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
  description = "Default availability zone for VMs and volumes"
  type        = string
  default     = "sz1"
}

variable "provider_network_id" {
  description = "Network ID of the provider network"
  type        = string
  default     = "a2424481-1b98-4da4-ab0a-bad0a6479ecf"
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

variable "oci_compartment_id" {
  description = "OCI compartment ID"
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
  default     = "~/.config/oci/oci_api_key.pem"
}

variable "wasabi_region" {
  description = "Wasabi region"
  type        = string
  default     = "eu-central-2"
}

variable "wasabi_access_key" {
  description = "Wasabi root account access key"
  type        = string
  sensitive   = true
}

variable "wasabi_secret_key" {
  description = "Wasabi root account secret key"
  type        = string
  sensitive   = true
}

variable "healthchecksio_api_key" {
  description = "Healthchecks.io API key"
  type        = string
  sensitive   = true
}

variable "healthchecksio_api_url" {
  description = "Healthchecks.io API base URL"
  type        = string
}

# vim: set ft=terraform
