{
  lib,
  pkgs,
  stdenvNoCC,
  requireFile,
}:

stdenvNoCC.mkDerivation {
  pname = "ComicCode";
  version = "478c9f6";

  src = requireFile {
    name = "ILT-220422-478c9f6.zip";
    url = "https://blobs.brkn.lol/private/fonts/ILT-220422-478c9f6.zip";
    sha256 = "sha256-VS5kTzKd4Mi/kO68jEoLvvzv7AoFXs1eAN9XPJWAKSs=";
  };

  nativeBuildInputs = with pkgs; [ unzip ];

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
