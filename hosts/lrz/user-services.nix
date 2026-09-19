{ config, lib, ... }:
{
  # FNUC-013: keep fnuc's automation authoritative during staging. In particular,
  # do not import hosts/fnuc/default.nix or copy its home/service identities.
  home-manager.users.${config.mainUser.username} = {
    services = {
      jcalapi.enable = lib.mkForce false;
      ssh-clipboard.enable = lib.mkForce false;
      syncthing.enable = lib.mkForce false;
      home-manager.autoUpgrade.enable = lib.mkForce false;
    };

    # These shared modules otherwise schedule writes immediately after login.
    systemd.user.timers =
      lib.genAttrs
        [
          "mani"
          "mani-work"
          "taskwarrior-sync"
          "yadm-pull"
        ]
        (_: {
          Install.WantedBy = lib.mkForce [ ];
        });

    # Also prevent activation or manual starts from mutating a staged home.
    systemd.user.services =
      lib.genAttrs
        [
          "mani"
          "mani-work"
          "taskwarrior-sync"
          "yadm-clone"
          "yadm-pull"
          "zinit-install"
        ]
        (_: {
          Unit.ConditionPathExists = lib.mkForce "/run/lrz-user-jobs-approved";
        });

    home.activation.yadm-clone = lib.mkForce {
      after = [ "reloadSystemd" ];
      before = [ ];
      data = "";
    };
  };
}
