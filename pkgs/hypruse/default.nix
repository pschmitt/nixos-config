{
  lib,
  buildPythonApplication,
  fetchurl,
  hatchling,
  hyprland,
  makeWrapper,
  mcp,
  grim,
  systemd,
  wl-clipboard,
  wtype,
}:

buildPythonApplication rec {
  pname = "hypruse";
  version = "0.15.1";

  src = fetchurl {
    url = "https://github.com/IlyasKhallouki/hypruse/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-Y2S16i1eelTWbXiQ2GeDWmKY/QbZ6Mzo01heX6CUpTo=";
  };

  pyproject = true;
  nativeBuildInputs = [
    hatchling
    makeWrapper
  ];
  propagatedBuildInputs = [ mcp ];

  postFixup = ''
    wrapProgram $out/bin/hypruse \
      --prefix PATH : ${
        lib.makeBinPath [
          grim
          hyprland
          systemd
          wl-clipboard
          wtype
        ]
      }
  '';

  meta = {
    description = "Computer-use MCP server for Hyprland";
    homepage = "https://github.com/IlyasKhallouki/hypruse";
    license = lib.licenses.mit;
    mainProgram = "hypruse";
    platforms = lib.platforms.linux;
  };
}
