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
  version = "14.14.1";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-s5kzxzyfNGK57MtusjEjcm0Gn75Wu8vfwJEIaVz7m20=";
  };

  vendorHash = "sha256-ZiLYnEcugciobjAchzJZNQrE3G11ehf3vi6cIMxZiTQ=";

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
