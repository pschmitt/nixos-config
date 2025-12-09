{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "yank-osc52";
  version = "0-unstable-2025-12-02";

  src = fetchFromGitHub {
    owner = "sunaku";
    repo = "home";
    rev = "16952560fcb4ee1090185ecbfc78eff26a7cec3c";
    hash = "sha256-QuWwnlxhaHxQve++PhFjLrYTnKzjmM8GcK00zWn4f4M=";
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
    ];
  };

  installPhase = ''
    install -Dm755 bin/yank $out/bin/yank
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
