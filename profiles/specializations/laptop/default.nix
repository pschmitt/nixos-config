{ inputs, lib, ... }:
{
  hardware.cattle = false;

  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ../../../services/bitwarden.nix
    ../../../services/kmscon.nix
    ../../../services/nfs/nfs-client-all.nix
    ../../../services/nix-distributed-build.nix

    ../../features/network/sshfs.nix
    ../../features/network/ha-sshfs.nix

    ../../features/network/wifi.nix
    ./a11y.nix
    ./noctalia.nix
    ./initrd-network.nix
    ./initrd-wifi.nix
    ./managarr.nix
    ./noisetorch.nix
    ./network.nix
    ./power-profiles-daemon.nix
    ./restic.nix
    ./syncthing.nix
  ];

  # https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html
  services = {
    logind.settings.Login = {
      HandlePowerKey = lib.mkDefault "suspend"; # default is "poweroff"
      HandleLidSwitchExternalPower = lib.mkDefault "suspend";
    };

    # firmware updates
    fwupd.enable = true;
  };

  services.kmscon.config."font-size" = 30;
}
