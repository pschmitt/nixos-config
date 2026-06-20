{ lib, pkgs, ... }:
let
  nixDaemonOverride = pkgs.writeText "nix-daemon-fnuc-override.conf" ''
    [Service]
    CPUWeight=10
    CPUQuota=200%
    IOWeight=10
    MemoryHigh=4G
    MemoryMax=6G
    ManagedOOMMemoryPressure=kill
    ManagedOOMMemoryPressureLimit=40%
    TasksMax=4096
  '';
in
{
  home.activation.fnucNixDaemonOverride = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target_dir=/etc/systemd/system/nix-daemon.service.d
    target_file="$target_dir/override.conf"

    # fnuc is a standalone Home Manager host, so the system unit override has
    # to be installed from activation instead of a NixOS module.
    if ! /usr/bin/sudo -n true >/dev/null 2>&1
    then
      printf 'Skipping nix-daemon override update: passwordless sudo unavailable\n' >&2
    elif /usr/bin/sudo ${pkgs.coreutils}/bin/test -f "$target_file" \
      && /usr/bin/sudo ${pkgs.diffutils}/bin/cmp -s ${nixDaemonOverride} "$target_file"
    then
      :
    else
      /usr/bin/sudo ${pkgs.coreutils}/bin/install -d -m 0755 "$target_dir"
      /usr/bin/sudo ${pkgs.coreutils}/bin/install -m 0644 ${nixDaemonOverride} "$target_file"
      /usr/bin/sudo ${pkgs.systemd}/bin/systemctl daemon-reload
      /usr/bin/sudo ${pkgs.systemd}/bin/systemctl restart nix-daemon.service
    fi
  '';
}
