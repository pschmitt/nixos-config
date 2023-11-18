{ lib, pkgs, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "ComicCode";
  version = "478c9f6";

  # FIXME Why is fetchzip refusing to download this?
  # src = fetchurl {
  #   url = "file:///etc/nixos/pkgs/proprietary-fonts/ComicCode/ILT-220422-478c9f6.zip";
  #   sha256 = "sha256-VS5kTzKd4Mi/kO68jEoLvvzv7AoFXs1eAN9XPJWAKSs=";
  # };
  src = ../src/ILT-220422-478c9f6.zip;

  nativeBuildInputs = with pkgs; [
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/opentype
    unzip -j $src '*.otf' -d $out/share/fonts/opentype
    # remove demo fonts
    rm -f $out/share/fonts/opentype/*Demo*
  '';

  meta = with lib; {
    homepage = "https://tosche.net/fonts/comic-code";
    description = "Comic Code is a monospaced adaptation of the most infamous yet most popular casual font";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
