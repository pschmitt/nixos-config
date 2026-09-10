{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "playconsole-cli";
  version = "0.5.17";

  src = fetchFromGitHub {
    owner = "AndroidPoet";
    repo = "playconsole-cli";
    rev = "v${version}";
    hash = "sha256-79sOAyf2OlRbkGDdN4LD/jegi0GeNdHJx/pCgzmqrpw=";
  };

  vendorHash = "sha256-pJ1RHJmDJ2vSRv4Eq0GMQXYtkDUAmUDCELy2LvKnTCI=";

  subPackages = [ "cmd/playconsole-cli" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.commit=${src.rev}"
  ];

  postInstall = ''
    mv "$out/bin/playconsole-cli" "$out/bin/gpc"
  '';

  meta = {
    description = "Fast, lightweight, scriptable CLI for Google Play Console";
    homepage = "https://github.com/AndroidPoet/playconsole-cli";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "gpc";
  };
}
