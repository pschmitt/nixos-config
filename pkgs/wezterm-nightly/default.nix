{ stdenvNoCC, fetchurl, appimageTools }:

appimageTools.wrapType2 {
  name = "wezterm-nightly";
  version = "1.0";

  src = fetchurl {
    url = "https://github.com/wez/wezterm/releases/download/nightly/WezTerm-nightly-Ubuntu20.04.AppImage";
    hash = "sha256-MqchYMF6HBLnbiK8bTuQxUTn89/fzSB5q8Mu54hiTYM=";

  };

  extraPkgs = pkgs: with pkgs; [ ];
}
