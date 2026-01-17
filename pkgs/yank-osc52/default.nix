{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "yank-osc52";
  version = "unstable-2026-01-13";

  src = fetchFromGitHub {
    owner = "sunaku";
    repo = "home";
    rev = "6f4487871996308df13f0a43a85a63a75ea5a5ea";
    hash = "sha256-k25pdQDx6mv2/hPK8HFniYvsllMBjKGwH/7oI9LS1OI=";
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
