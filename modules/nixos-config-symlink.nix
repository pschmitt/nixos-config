{ config, lib, ... }:
let
  cfg = config.custom.nixosConfigSymlink;

  repoDir = "${config.mainUser.homeDirectory}/devel/private/pschmitt/nixos-config.git";
in
{
  options.custom.nixosConfigSymlink = {
    enable = lib.mkEnableOption "managing /etc/nixos as a symlink into the devel checkout";
  };

  config = lib.mkIf cfg.enable {
    # Non-forcing `L`: only creates the symlink if /etc/nixos doesn't already
    # exist, so an already-populated legacy checkout (the common case on
    # hosts not yet manually migrated, see AGENTS.md) is left untouched. On a
    # fresh host this dangles until repoDir is cloned there by hand.
    systemd.tmpfiles.rules = [
      "L /etc/nixos - - - - ${repoDir}"
    ];
  };
}
