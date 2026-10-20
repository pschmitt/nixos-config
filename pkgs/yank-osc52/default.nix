{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "yank-osc52";
  version = "unstable-2026-10-20";

  src = fetchFromGitHub {
    owner = "sunaku";
    repo = "home";
    rev = "48c4a07c8e8d2ff377da392bc05cc1d4b48d07c1";
    hash = "sha256-12CfPcZFhTrLKt5GRWlwRMf4Qdrv/BYUF7PZs7nNi88=";
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

  meta = {
    description = "OSC52 clipboard helper that works in terminals, tmux, and X11";
    homepage = "https://sunaku.github.io/tmux-yank-osc52.html";
    license = lib.licenses.isc;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "yank";
    platforms = lib.platforms.all;
  };
}
