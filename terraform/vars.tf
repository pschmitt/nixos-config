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

# vim: set ft=terraform
