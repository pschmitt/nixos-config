{
  lib,
  pkgs,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "obs-freeze-filter-bin";
  version = "0.3.3";

  src = fetchurl {
    url = "https://obsproject.com/forum/resources/freeze-filter.950/version/4603/download?file=89158";
    sha256 = "sha256-nMPdtnmAXkHP3k/8O2/geqdAOQbugGE030XHyo4mJwQ=";
  };

  nativeBuildInputs = with pkgs; [ unzip ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    tmpdir=tmp-out
    mkdir -p "$tmpdir"
    unzip "$src" -d "$tmpdir"

    dest="$out/obs-plugins/obs-freeze-filter"
    mkdir -p "$dest"

    tar -xzvf tmp-out/*22.04*.tar.gz -C "$tmpdir"
    cp -a "$tmpdir"/freeze-filter/* "$dest"
  '';

  meta = with lib; {
    homepage = "https://github.com/exeldro/obs-freeze-filter";
    description = " Plugin for OBS Studio to freeze a source using a filter ";
    license = licenses.gpl2Only;
    platforms = platforms.all;
  };
}
