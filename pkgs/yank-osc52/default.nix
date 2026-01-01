{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "yank-osc52";
  version = "unstable-2025-12-31";

  src = fetchFromGitHub {
    owner = "sunaku";
    repo = "home";
    rev = "e7d8d60a3896797e72b71a8f546b14e5d604124d";
    hash = "sha256-1oN0Ifi73ic0f2EkiPT3HplIkHGWqbPt6MXfU0TFUlg=";
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
      "--version-regex"
      "(?:0-)?(unstable-[0-9]{4}-[0-9]{2}-[0-9]{2})"
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    patchShebangs bin/yank
  '';

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
