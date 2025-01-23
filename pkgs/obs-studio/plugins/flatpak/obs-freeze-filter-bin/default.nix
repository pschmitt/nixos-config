{
  lib,
  pkgs,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "obs-freeze-filter-bin";
  version = "0.3.4";

  src = fetchurl {
    url = "https://obsproject.com/forum/resources/freeze-filter.950/version/6048/download?file=110877";
    sha256 = "sha256-zPRMry3NCY8CfpKU+p9GmVrs8qgzcMMcvmE5bVA7igU=";
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
