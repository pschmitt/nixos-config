{ config, pkgs, ... }:
{
  sops.secrets."bitwarden/password" = {
    inherit (config.custom) sopsFile;
    owner = config.mainUser.username;
  };

  # NOTE For the biometrics to work, the bitwarden-deskop pkg must be installed
  # as a system package. See:
  # https://github.com/NixOS/nixpkgs/pull/339384
  environment.systemPackages = with pkgs; [
    bitwarden-desktop
  ];
}
