{ lib
, pkgs
, stdenvNoCC
, fetchzip
, python3Packages
}:

stdenvNoCC.mkDerivation rec {
  pname = "MonoLisa";
  version = "1.808";

  src = ./MonoLisa-Plus-1.808-otf.zip;

  nativeBuildInputs = with pkgs; [
    nerd-font-patcher
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/opentype extracted
    unzip -j $src -d extracted

    for f in extracted/*
    do
      # Copy original font
      cp $f $out/share/fonts/opentype

      # Nerdify font
      nerd-font-patcher $f --complete --no-progressbars \
        --outputdir $out/share/fonts/opentype
    done
  '';

  meta = with lib; {
    homepage = "https://www.monolisa.dev";
    description = "font follows function";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
