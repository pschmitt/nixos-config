{
  lib,
  pkgs,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "obs-replay-source-bin";
  version = "1.8.0";

  # To fetch the right url visit the url below:
  # https://obsproject.com/forum/resources/replay-source.686/download
  src = fetchurl {
    url = "https://obsproject.com/forum/resources/replay-source.686/version/5778/download?file=106473";
    sha256 = "sha256-sEtSjlmEMZkjYmDlzFCT30mw0QWErLTgy+HVkc0OuL8=";
  };

  nativeBuildInputs = with pkgs; [ unzip ];

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
    platforms = platforms.linux;
  };
}
