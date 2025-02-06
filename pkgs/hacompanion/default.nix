{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "hacompanion";
  version = "1.0.21";

  src = fetchFromGitHub {
    owner = "tobias-kuendig";
    repo = "hacompanion";
    rev = "v${version}";
    hash = "sha256-6fj9Gs/ezISx5Llele5mrTFR0IiQzzm1wWcAywTaFPk=";
  };

  vendorHash = "sha256-y2eSuMCDZTGdCs70zYdA8NKbuPPN5xmnRfMNK+AE/q8=";

  ldflags = [
    "-s"
    "-w"
    "-X=main.Version=${version}"
  ];

  meta = with lib; {
    description = "Daemon that sends local hardware information to Home Assistant";
    homepage = "https://github.com/tobias-kuendig/hacompanion";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "hacompanion";
  };
}
