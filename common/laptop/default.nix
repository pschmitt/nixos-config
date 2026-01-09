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
    ./power-profiles-daemon.nix
    ./restic.nix
    ./waydroid.nix
    ./wireshark.nix
  ];

  # https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html
  services.logind.settings.Login = {
    HandlePowerKey = lib.mkDefault "suspend"; # default is "poweroff"
    HandleLidSwitchExternalPower = lib.mkDefault "suspend";

    # firmware updates
    fwupd.enable = true;
  };
}
