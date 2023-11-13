{ lib, pkgs }:

pkgs.stdenv.mkDerivation rec {
  pname = "proprietary-fonts";
  version = "0.1.0";

  src = ./fonts.zip;

  phases = [ "installPhase" ];
  buildInputs = [ pkgs.unzip ];

  installPhase = ''
    mkdir -p $out/share/fonts/truetype $out/share/fonts/opentype extracted
    # DEBUG
    ls -la ${src}
    unzip -o $src -d extracted
    find extracted -iname '*.ttf' -exec mv {} $out/share/fonts/truetype \;
    find extracted -iname '*.otf' -exec mv {} $out/share/fonts/opentype \;
  '';

  meta = with lib; {
    description = "Comic Code TTF Font (with NerdFont patches)";
    homepage = "https://tosche.net/fonts/comic-code";
    license = licenses.unfree;
    maintainers = with maintainers; [ pschmitt ];
  };
}
