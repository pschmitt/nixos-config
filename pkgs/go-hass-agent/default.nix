# Based off of:
# https://github.com/nix-community/nur-combined/blob/main/repos/sebrut/pkgs/go-hass-agent/default.nix

{
  lib,
  pkgs,
  buildGo127Module,
  ...
}:

# go.mod requires Go >= 1.27.3.
buildGo127Module rec {
  pname = "go-hass-agent";
  version = "14.19.0";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-ApaNeScISB3qVUZ7aDAjL/ufNvm7VhB/NhdmPBB3cS0=";
  };

  vendorHash = "sha256-+JCAolvTS/gkHZg9x1aLg6x9b6NJoXT/FY9V96ojFq8=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/joshuar/go-hass-agent/config.AppVersion=${version}"
  ];

  doCheck = false;

  meta = {
    description = "A Home Assistant, native app for desktop/laptop devices.";
    homepage = "https://github.com/joshuar/go-hass-agent";
    changelog = "https://github.com/joshuar/go-hass-agent/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "go-hass-agent";
  };
}
