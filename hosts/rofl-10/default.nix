{
  imports = [
    ../../profiles/base/users/github-actions.nix
    ../../profiles/base/users/k8s-backdoor.nix
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./browserless-public.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./nix-cache.nix
    ./rclone-bisync.nix
    ./service-identities.nix
    ./services.nix
    ./storage.nix
  ];

  # FIXME: Remove this exception as soon as the pinned NetBox package no longer
  # pulls python-jose 3.5.0 through social-auth-core's OpenID Connect extra, or
  # Nixpkgs ships a python-jose release patched for CVE-2026-120459.
  # This bypasses the insecure-package guard for this host's NetBox closure.
  nixpkgs.config.permittedInsecurePackages = [ "python3.14-python-jose-3.5.0" ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
