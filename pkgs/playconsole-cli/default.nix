{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "playconsole-cli";
  version = "0.5.15";

  src = fetchFromGitHub {
    owner = "AndroidPoet";
    repo = "playconsole-cli";
    rev = "v${version}";
    hash = "sha256-QOCp1C3/uPzjfPUWBBVOcEwmwy7yVwiUOt15CTM0Fl0=";
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
