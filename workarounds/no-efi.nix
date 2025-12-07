{ lib, ... }:
{
  # Create a MBR-only ISO
  # overrides https://github.com/NixOS/nixpkgs/blob/6445eabef27a633d272e887bf762094c44e49af1/nixos/modules/installer/cd-dvd/installation-cd-base.nix#L24
  isoImage.makeEfiBootable = lib.mkForce false;
  isoImage.makeUsbBootable = lib.mkForce false;
}
