{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global
    ../../common/mail
    ../../common/network
    ../../common/network/wifi.nix

    # XXX Below imports initrd-luks-ssh-unlock etc
    # ../../server
    # So we only import what we really need here:
    ../../server/dotfiles.nix
    # ../../monit.nix
    # ../../netbird.nix
    # ../../restic.nix

    # Set hostkeys
    # XXX This is circular dependency!
    # ./ssh.nix

    ./picamera.nix
    ../../services/mediamtx.nix
  ];

  custom = {
    cattle = true;
    kvmGuest = false;
    raspberryPi = true;
  };

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

  # FIXME nodejs_22 does not built currently on aarch64-linux (2025-09-07)
  programs.npm.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    curl
    dnsutils
    gitMinimal
    htop
    jq
    tmux
    tmux-slay
  ];

  users.users."${config.custom.username}".extraGroups = [ "networkmanager" ];
}
