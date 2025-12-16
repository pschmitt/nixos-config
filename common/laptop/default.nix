{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ../../services/bitwarden.nix
    ../../services/nfs/nfs-client-all.nix
    ../../services/nix-distributed-build.nix

    ../../common/network/snek
    ../../common/network/sshfs.nix

    ../network/wifi.nix
    ./a11y.nix
    ./initrd-network.nix
    ./media.nix
    ./network.nix
    ./restic.nix
    ./waydroid.nix
    ./wireshark.nix
  ];

  # power-profiles-daemon conflicts with tlp
  # https://linrunner.de/tlp/faq/ppd.html
  services = {
    power-profiles-daemon.enable = lib.mkForce true;
    tlp.enable = lib.mkForce false;

    # https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html
    logind.settings.Login = {
      HandlePowerKey = lib.mkDefault "suspend"; # default is "poweroff"
      HandleLidSwitchExternalPower = lib.mkDefault "suspend";
    };
  };
}
