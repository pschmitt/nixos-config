# A nixos-anywhere kexec installer tarball for OCI hosts, with the
# oci-consistent-device-naming udev rule baked in so /dev/oracleoci/oraclevdX
# device paths already resolve during disko partitioning - normally that
# naming only appears once the target's own final NixOS config is booted
# (see hardware/oci.nix), not during the ephemeral kexec+disko install
# phase, which runs nixos-anywhere's own generic installer image instead of
# ours.
#
# Composition mirrors nixos-images' own flake.nix exactly (the
# `kexec-installer = nixpkgs: module: ...` helper it uses to build its own
# variants), just with our extra module added to the list:
#   (nixpkgs.legacyPackages.${system}.nixos [ module self.nixosModules.kexec-installer ]).config.system.build.kexecInstallerTarball
#
# Usage (tofu): pass this derivation's tarball path as `kexec_tarball_url`
# on the nixos-host module (it's uploaded, not fetched, despite the name -
# see modules/nixos-host and nixos-anywhere's --kexec flag).
{
  inputs,
  oci-consistent-device-naming,
  system ? "aarch64-linux",
}:
let
  inherit (inputs) nixos-images;
  nixpkgs = nixos-images.inputs.nixos-unstable;
in
(nixpkgs.legacyPackages.${system}.nixos [
  {
    services.udev.packages = [ oci-consistent-device-naming ];
    system.kexec-installer.name = "nixos-kexec-installer-oci-udev";
    imports = [ nixos-images.nixosModules.noninteractive ];
  }
  nixos-images.nixosModules.kexec-installer
]).config.system.build.kexecInstallerTarball
