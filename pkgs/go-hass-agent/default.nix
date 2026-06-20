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
  version = "14.13.0";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-sTVY4lWM+JkYMeh9mIHYmkQ4k4fwlAW2GbO8tLle7Nw=";
  };

  vendorHash = "sha256-x00RN12V9FCHYwr1SLc0MeZ7rH2cCd0wyyXiBLeDsWI=";

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
