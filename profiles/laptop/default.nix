{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ../../services/bitwarden.nix
    ../../services/nfs/nfs-client-all.nix
    ../../services/nix-distributed-build.nix

    ../network/sshfs.nix
    ../network/ha-sshfs.nix

    ../network/wifi.nix
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
    kmscon = {
      enable = true;
      config = {
        hwaccel = true;
        "font-name" = "Comic Code";
        "font-size" = 30;
      };
    };

    logind.settings.Login = {
      HandlePowerKey = lib.mkDefault "suspend"; # default is "poweroff"
      HandleLidSwitchExternalPower = lib.mkDefault "suspend";
    };

    # firmware updates
    fwupd.enable = true;
  };
}
