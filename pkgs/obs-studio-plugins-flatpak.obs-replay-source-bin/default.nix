{ lib, pkgs, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation {
  pname = "obs-replay-source-bin";
  version = "1.6.2";

  src = fetchurl {
    url = "https://obsproject.com/forum/resources/replay-source.686/version/4903/download?file=94066";
    sha256 = "sha256-eIoHVD5czfHUzeSlC8Yude7QF0HwTIUc/VZImHxAots=";
  };

  nativeBuildInputs = with pkgs; [
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    tmpdir=tmp-out
    mkdir -p "$tmpdir"
    unzip "$src" -d "$tmpdir"

    dest="$out/obs-plugins/obs-replay-source"
    mkdir -p "$dest"

    tar -xzvf tmp-out/*22.04*.tar.gz -C "$tmpdir"
    cp -a "$tmpdir"/replay-source/* "$dest"
  '';

  meta = with lib; {
    homepage = "https://github.com/exeldro/obs-replay-source";
    description = "Replay source for OBS studio";
    license = licenses.gpl2Only;
    platforms = platforms.all;
  };
}
