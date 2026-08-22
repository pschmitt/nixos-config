{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ccimgd;
  sockPath = "${config.home.homeDirectory}/.cache/ccimgd.sock";

  # Speaks to the remote wl-paste shim (see hosts/fnuc/wl-paste-shim.nix):
  # reads newline-separated argv terminated by a blank line, runs the real
  # wl-paste with those args, and replies with a "STATUS <rc>" line followed
  # by wl-paste's raw stdout.
  handler = pkgs.writeShellApplication {
    name = "ccimgd-handler";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.wl-clipboard
    ];
    text = ''
      args=()
      while IFS= read -r line; do
        [[ -z $line ]] && break
        args+=("$line")
      done

      out=$(mktemp)
      trap 'rm -f "$out"' EXIT

      set +e
      wl-paste "''${args[@]}" >"$out" 2>/dev/null
      rc=$?
      set -e

      printf 'STATUS %d\n' "$rc"
      cat "$out"
    '';
  };
in
{
  options.services.ccimgd = {
    enable = lib.mkEnableOption "local clipboard bridge for the remote SSH wl-paste shim";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.ccimgd = {
      Unit = {
        Description = "Clipboard bridge for the remote SSH wl-paste shim";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${sockPath}";
        ExecStart = "${pkgs.socat}/bin/socat UNIX-LISTEN:${sockPath},fork,unlink-early=1 EXEC:${lib.getExe handler}";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -f ${sockPath}";
        Restart = "on-failure";
        RestartSec = 2;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
