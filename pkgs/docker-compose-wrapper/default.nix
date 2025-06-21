{
  lib,
  stdenv,
  makeWrapper,
  bash,
  docker,
  gnused,
}:

stdenv.mkDerivation {
  pname = "docker-compose-wrapper";
  version = "0.1";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/docker-compose-wrapper.sh $out/bin/docker-compose-wrapper
    chmod +x $out/bin/docker-compose-wrapper

    wrapProgram $out/bin/docker-compose-wrapper \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          docker
          gnused
        ]
      }
  '';

  meta = with lib; {
    description = "Wrapper around docker-compose that loads /etc/containers/env/*.env";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    platforms = platforms.all;
  };
}
