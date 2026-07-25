# Based off of:
# https://github.com/nix-community/nur-combined/blob/main/repos/sebrut/pkgs/go-hass-agent/default.nix

{
  lib,
  pkgs,
  buildGoModule,
  ...
}:

buildGoModule rec {
  pname = "go-hass-agent";
  version = "14.15.0";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-5x9SNfqzUltN0bXQJ/6iMbW2TBbX2OF2MuZOzC1Wjn4=";
  };

  vendorHash = "sha256-8aEpjky5v6RlKOevphK0oetUpMvGJ5OhnRekFr3nhoE=";

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
