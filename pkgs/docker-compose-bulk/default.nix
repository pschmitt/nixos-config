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
    rev = "e164dbb4cc7c6cca02285a8ea3f814001855c69b";
    hash = "sha256-QopOndmMydhuX4HBrWwRTJpx9c6kRV/cvPxZTzK6Xbg=";
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
