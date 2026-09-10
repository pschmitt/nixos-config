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
    # Noctalia is the default bar (see profiles/laptop/noctalia.nix); DMS is
    # re-enabled alongside it as an opt-in alternative, reachable via
    # SUPER+SHIFT+B (toggle-bar.sh) — see profiles/laptop/dank-material-shell.nix.
    ./dank-material-shell.nix
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
