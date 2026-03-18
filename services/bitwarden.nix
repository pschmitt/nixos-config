{ config, pkgs, ... }:
{
  sops.secrets."bitwarden/password" = {
    inherit (config.custom) sopsFile;
    owner = config.mainUser.username;
  };

  # NOTE For the biometrics to work, the bitwarden-deskop pkg must be installed
  # as a system package. See:
  # https://github.com/NixOS/nixpkgs/pull/339384
  # FIXME this fails to build as of Wed Mar 18 01:48:35 PM CET 2026
  # environment.systemPackages = with pkgs; [
  #   bitwarden-desktop
  # ];
}
