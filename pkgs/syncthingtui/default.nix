{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "syncthingtui";
  version = "1.0.3";

  src = fetchFromGitHub {
    owner = "Evidlo";
    repo = "syncthingtui";
    rev = "v${version}";
    hash = "sha256-BtikvNJRn6TpxCoq6/U8TUSkH0JsvRDGqr4HQ1rk1Ws=";
  };

  vendorHash = "sha256-ryvE7cnGhd9JQRuQwKoyl3f4XUvK4RKwLEeBMozbRwU=";

  subPackages = [ "cmd/syncthingtui" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Syncthing TUI client, near feature-parity with the web GUI";
    homepage = "https://github.com/Evidlo/syncthingtui";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "syncthingtui";
  };
}
