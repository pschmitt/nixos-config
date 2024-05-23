{
  lib,
  pkgs,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "obs-text-pthread-bin";
  version = "2.0.2";

  src = fetchurl {
    url = "https://github.com/norihiro/obs-text-pthread/releases/download/2.0.2/obs-text-pthread-2.0.2-obs28-ubuntu-20.04-x86_64.deb";
    sha256 = "sha256-N1E5DZ7wrYKN+aut/vjzvf6s6LA64OeSYYruIe5jkXU=";
  };

  phases = [ "buildPhase" ];

  nativeBuildInputs = [ pkgs.dpkg ];

  buildPhase = ''
    dest="$out/obs-plugins/obs-text-pthread"
    tmpout="tmp-out"
    mkdir -p "$tmpout" "$dest"
    dpkg -x "$src" "$tmpout"

    install -Dm 644 $tmpout/usr/lib/*/obs-plugins/obs-text-pthread.so \
      "$dest/bin/64bit/obs-text-pthread.so"
    install -Dm 644 $tmpout/usr/share/obs/obs-plugins/obs-text-pthread/textalpha.effect \
      "$dest/data/textalpha.effect"
  '';

  meta = with lib; {
    homepage = "https://github.com/norihiro/obs-text-pthread";
    description = "Rich text source plugin for OBS Studio";
    license = licenses.gpl2Only;
    platforms = platforms.all;
  };
}
