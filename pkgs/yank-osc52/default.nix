{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "yank-osc52";
  version = "2024-10-04";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/sunaku/home/master/bin/yank";
    sha256 = "sha256-iM6zeh35uBO+xSDnMCWM/QZz28wmrumyQIh35QUqE1g=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 ${src} $out/bin/yank
  '';

  meta = with lib; {
    description = "OSC52 clipboard helper that works in terminals, tmux, and X11";
    homepage = "https://sunaku.github.io/tmux-yank-osc52.html";
    license = licenses.isc;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "yank";
    platforms = platforms.all;
  };
}
