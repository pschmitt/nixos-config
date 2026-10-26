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
  version = "14.18.0";

  src = pkgs.fetchFromGitHub {
    owner = "joshuar";
    repo = "go-hass-agent";
    rev = "v${version}";
    hash = "sha256-P4FECABO2Kq5wxTvkVyv6//fsqOR6EoIqe506MOXBto=";
  };

  vendorHash = "sha256-x1qanfl5qe3dvFgmSrQqsZqL7ON8Cj7veyYdSL3ocgU=";

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
