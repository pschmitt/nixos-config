{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global
    ../../services/mail
    ../../common/network
    ../../common/network/wifi.nix

    # XXX Below imports initrd-luks-ssh-unlock etc
    # ../../common/server
    # So we only import what we really need here:
    ../../common/server/dotfiles.nix
    # ../../monit.nix
    # ../../netbird.nix
    # ../../restic.nix

    # Set hostkeys
    # XXX This is circular dependency!
    # ./ssh.nix

    ./picamera.nix
    ../../services/mediamtx.nix
  ];

  custom.cattle = true;
  hardware.kvmGuest = false;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);

    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };

    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };

    wireless = {
      enable = true;
      userControlled.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    dnsutils
    gitMinimal
    htop
    jq
    tmux
    inputs.tmux-slay.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  users.users."${config.custom.username}".extraGroups = [ "networkmanager" ];
}
