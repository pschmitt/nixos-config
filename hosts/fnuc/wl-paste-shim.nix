# Claude Code expects Wayland clipboard commands on fnuc, while ssh-clipboard
# uses its private Xvfb display there. These shims keep the familiar command
# names and expose the X11 clipboard populated by the ssh-clipboard daemon.
{ pkgs, ... }:
let
  wlPasteShim = pkgs.writeShellApplication {
    name = "wl-paste";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.xclip
    ];
    text = builtins.readFile ./scripts/wl-paste.sh;
  };

  wlCopyShim = pkgs.writeShellApplication {
    name = "wl-copy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.perl
      pkgs.xclip
    ];
    text = builtins.readFile ./scripts/wl-copy.sh;
  };
in
{
  home.packages = [
    wlCopyShim
    wlPasteShim
  ];
}
