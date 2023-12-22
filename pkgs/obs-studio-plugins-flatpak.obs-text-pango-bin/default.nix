{ lib, stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation {
  pname = "obs-text-pango-bin";
  version = "1.0";

  src = fetchzip {
    url = "https://github.com/kkartaltepe/obs-text-pango/releases/download/v1.0/text-pango-linux.tar.gz";
    sha256 = "sha256-PUA/UvbWFHXwTQA/7WfsL9H1ilrcDTlaJkoB4P9VTtg=";
  };

  phases = [ "buildPhase" ];

  buildPhase = ''
    dest="$out/obs-plugins/obs-text-pango"
    mkdir -p "$dest"
    cp -r "$src/bin" "$src/data" "$dest"
  '';

  meta = with lib; {
    homepage = "https://github.com/kkartaltepe/obs-text-pango";
    description = "Text Source using Pango for OBS Studio";
    license = licenses.gpl2Only;
    platforms = platforms.all;
  };
}
