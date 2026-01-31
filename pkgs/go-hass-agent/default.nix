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
  version = "14.5.0";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-0aNQgBLZQKoJmq3iOUmBwD9mU7nyTRf10PPmbck0WIc=";
  };

  vendorHash = "sha256-BcqlkJx7WnmAqcgbgvIJs8Y0lg/c1uUi8AzmbpAqlOU=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/joshuar/go-hass-agent/config.AppVersion=${version}"
  ];

  meta = {
    description = "A Home Assistant, native app for desktop/laptop devices.";
    homepage = "https://github.com/joshuar/go-hass-agent";
    changelog = "https://github.com/joshuar/go-hass-agent/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "go-hass-agent";
  };
}
