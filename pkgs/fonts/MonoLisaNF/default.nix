{
  lib,
  pkgs,
  stdenvNoCC,
  requireFile,
}:

let
  source = {
    name = "MonoLisa-Plus-1.808-otf.zip";
    url = "https://blobs.brkn.lol/private/fonts/MonoLisa-Plus-1.808-otf.zip";
    sha256 = "sha256-t66It78U6qH/2hgDa9EidNOcxfqkYOGrZ4Mb4oO/Lw0=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "MonoLisaNF";
  version = "1.808";

  src = requireFile source;
  # NOTE: This is required for us to be able to get the urls programatically
  # in the fetch-proprietary-garbage.sh script
  passthru.proprietarySource = source;

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
      # patch font
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
