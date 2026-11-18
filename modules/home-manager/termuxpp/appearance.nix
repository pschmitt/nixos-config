{
  config,
  lib,
  pkgs,
  ...
}:
let
  assets = lib.escapeShellArg "${config.xdg.configHome}/termuxpp";
  font = "${pkgs.ComicCodeNF}/share/fonts/opentype/ComicCodeLigaturesNerdFont-Regular-resized.otf";
in
{
  # Android reads these files outside the guest, where guest store links cannot be followed.
  home.activation.termuxppAppearance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/mkdir -p ${assets}
    run ${pkgs.coreutils}/bin/install -m 0600 ${./colors.properties} ${assets}/colors.properties
    run ${pkgs.coreutils}/bin/install -m 0600 ${font} ${assets}/font.ttf
  '';
}
