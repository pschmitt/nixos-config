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

  hardware.cattle = true;
  hardware.kvmGuest = false;

  # NOTE The leds conflict with the bluetooth device tree overlay, so we need
  # to disable them to keep bluetooth working.
  # hardware.raspberry-pi."4".bluetooth.enable = true;
  # hardware.bluetooth = {
  #   enable = true;
  # };
  # Keep bluetooth enabled while disabling LED overrides that conflict on
  # hardware.deviceTree.filter.
  # hardware.raspberry-pi."4".leds = {
  #   act.disable = lib.mkForce false;
  #   eth.disable = lib.mkForce false;
  #   pwr.disable = lib.mkForce false;
  # };

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
      userControlled = true;
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

  users.users."${config.mainUser.username}".extraGroups = [ "networkmanager" ];
}
