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
    # DMS is kept but intentionally not imported while trying Noctalia as
    # the default bar instead — see profiles/laptop/noctalia.nix. The file
    # is kept (not deleted) so switching back is a one-line revert.
    # ./dank-material-shell.nix
    ./noctalia.nix
    ./initrd-network.nix
    ./initrd-wifi.nix
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
}
