{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, bash
, docker
}:

stdenv.mkDerivation {
  pname = "docker-compose-bulk";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "docker-compose-bulk";
    rev = "6e8d1856eed21d3a39df5c49d7b2f37a50c05247";
    hash = "sha256-vDWe2N+NEEH/c9D8fvfZ1e8lVRmGTrLpSyF16PwAF0I=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/docker-compose-bulk $out/bin/docker-compose-bulk
    chmod +x $out/bin/docker-compose-bulk
    # Assuming you might need to wrap the script to include dependencies:
    wrapProgram $out/bin/docker-compose-bulk --prefix PATH : ${lib.makeBinPath [ bash docker ]}
  '';

  meta = with lib; {
    description = "Simple docker compose wrapper to perform bulk operations.";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "docker-compose-bulk";
    platforms = platforms.all;
  };
}
