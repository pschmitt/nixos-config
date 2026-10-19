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
  version = "0.13.0";

  src = fetchurl {
    url = "https://github.com/IlyasKhallouki/hypruse/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-azVNDgPFL25HJ6/UbUbHRNWrHz0ytZicEAkKEK13Huc=";
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
