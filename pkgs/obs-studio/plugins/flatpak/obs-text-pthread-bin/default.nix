{
  lib,
  pkgs,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "obs-text-pthread-bin";
  version = "2.0.5";

  src = fetchurl {
    url = "https://github.com/norihiro/obs-text-pthread/releases/download/${version}/obs-text-pthread-${version}-obs28-ubuntu-20.04-x86_64.deb";
    hash = "sha256-PTsxjdi619U4/PL6p3ZPJJMJZa053CwwEKffbWn2YAQ=";
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
