{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.nixosConfigSymlink;

  script = pkgs.writeShellApplication {
    name = "nixos-config-symlink";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = builtins.readFile ./scripts/nixos-config-symlink.sh;
  };
in
{
  options.custom.nixosConfigSymlink = {
    enable = lib.mkEnableOption "managing /etc/nixos as a symlink into the devel checkout";
  };

  config = lib.mkIf cfg.enable {
    # Idempotent, non-destructive: no-ops if /etc/nixos is already the
    # symlink, or already a populated checkout (the common case on hosts that
    # haven't been manually migrated to the devel-checkout convention yet —
    # see AGENTS.md). Only actually clones + links on a host where /etc/nixos
    # is missing or empty, e.g. a fresh install.
    system.activationScripts.nixosConfigSymlink = {
      deps = [ "users" ];
      text = ''
        NIXOS_CONFIG_HOME=${lib.escapeShellArg config.mainUser.homeDirectory} \
        NIXOS_CONFIG_USER=${lib.escapeShellArg config.mainUser.username} \
        ${script}/bin/nixos-config-symlink
      '';
    };
  };
}
