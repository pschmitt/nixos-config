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
    rev = "c9cef6aba25f86a941bede6c488b930b3bb077a6";
    hash = "sha256-6Gp3QvhrMJqPgQFMFVqUMFzq+XR6/L3IvyqrwQ3y4RQ=";
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
