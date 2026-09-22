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
