{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  bash,
  docker,
}:

stdenv.mkDerivation {
  pname = "docker-compose-bulk";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "docker-compose-bulk";
    rev = "d7c49950823a36dd682288bfcbd78105b5645c5d";
    hash = "sha256-ZUqM0XH+kZGvQyxkYCqSITa5EsPbuedxyYAIvgOCdI4=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/docker-compose-bulk $out/bin/docker-compose-bulk
    chmod +x $out/bin/docker-compose-bulk
    # Assuming you might need to wrap the script to include dependencies:
    wrapProgram $out/bin/docker-compose-bulk --prefix PATH : ${
      lib.makeBinPath [
        bash
        docker
      ]
    }
  '';

  meta = with lib; {
    description = "Simple docker compose wrapper to perform bulk operations.";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "docker-compose-bulk";
    platforms = platforms.all;
  };
}
