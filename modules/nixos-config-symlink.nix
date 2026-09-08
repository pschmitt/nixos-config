{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.nixosConfigSymlink;

  repoDir = "${config.mainUser.homeDirectory}/devel/private/pschmitt/nixos-config.git";

  cloneScript = pkgs.writeShellApplication {
    name = "nixos-config-clone";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = builtins.readFile ./scripts/nixos-config-clone.sh;
  };
in
{
  options.custom.nixosConfigSymlink = {
    enable = lib.mkEnableOption "managing /etc/nixos as a symlink into the devel checkout";
  };

  config = lib.mkIf cfg.enable {
    # Non-forcing `L`: only creates the symlink if /etc/nixos doesn't already
    # exist, so an already-populated legacy checkout (the common case on
    # hosts not yet manually migrated, see AGENTS.md) is left untouched. A
    # fresh host gets a symlink here even before the clone below has run —
    # it just dangles until then.
    systemd.tmpfiles.rules = [
      "L /etc/nixos - - - - ${repoDir}"
    ];

    # The one part tmpfiles can't do declaratively: populate repoDir itself
    # on a fresh host. Never touches /etc/nixos.
    systemd.services.nixos-config-clone = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [
          "NIXOS_CONFIG_HOME=${config.mainUser.homeDirectory}"
          "NIXOS_CONFIG_USER=${config.mainUser.username}"
        ];
        ExecStart = "${cloneScript}/bin/nixos-config-clone";
      };
    };
  };
}
