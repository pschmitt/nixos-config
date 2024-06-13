{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "hacompanion";
  version = "1.0.15";

  src = fetchFromGitHub {
    owner = "tobias-kuendig";
    repo = "hacompanion";
    rev = "v${version}";
    hash = "sha256-FR2IowbaHXr9x/eMt+NCuGusMwX2iVxPOuWEkhH2GFM=";
  };

  vendorHash = "sha256-ZZ8nxN+zUeFhSXyoHLMgzeFllnIkKdoVnbVK5KjrLEQ=";

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
