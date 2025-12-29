{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "yank-osc52";
  version = "unstable-2025-12-24";

  src = fetchFromGitHub {
    owner = "sunaku";
    repo = "home";
    rev = "8d98366cd3d7f3d9de32b6664d01556efbdfb1a8";
    hash = "sha256-VXyX6eoNxtW7WfNInOU8ZyzgLd9pfbmxz71O06n5BrY=";
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
