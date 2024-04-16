variable "availability_zone" {
  description = "Availability zone for the VM"
  type        = string
  default     = "es1"
}

variable "public_ssh_key" {
  description = "Public SSH key for accessing the VM"
  type        = string
  # default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOsodZo47l6by834BZ52mEI14gIs7GRxpRRAnocWlA2 pschmitt@x13"
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICGaXDkL/WvelHGLTp0j19arX3l0TLXUsxMyMhJUIuu+ pschmitt@ge2"
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