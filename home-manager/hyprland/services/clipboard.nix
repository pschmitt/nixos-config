{ lib, pkgs, ... }:
let
  inherit (lib) escapeShellArgs getExe;
  wlClipPersist = getExe pkgs.wl-clip-persist;
  wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
  cliphist = lib.getExe' pkgs.cliphist "cliphist";

  mkClipboardService =
    description: execArgs:
    {
      Unit = {
        Description = description;
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = escapeShellArgs execArgs;
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
in
{
  systemd.user.services = {
    clipboard-persist = mkClipboardService "Persist clipboard contents" [
      wlClipPersist
      "--clipboard"
      "both"
    ];

    clipboard-cliphist-text = mkClipboardService "Record text selections into cliphist" [
      wlPaste
      "--type"
      "text"
      "--watch"
      cliphist
      "store"
    ];

    clipboard-cliphist-image = mkClipboardService "Record image clipboard into cliphist" [
      wlPaste
      "--type"
      "image"
      "--watch"
      cliphist
      "store"
    ];
  };
}
