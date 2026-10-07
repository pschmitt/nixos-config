{
  lib,
  stdenvNoCC,
  writeShellApplication,
  coreutils,
  docker-client,
  file,
  findutils,
  gnugrep,
  gnutar,
}:

let
  dockerContext = stdenvNoCC.mkDerivation {
    pname = "termux-zinit-cache-docker-context";
    version = "1";
    src = lib.cleanSource ./.;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp prepare-termux-zinit-cache.sh "$out/"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "termux-zinit-cache";
  runtimeInputs = [
    coreutils
    docker-client
    file
    findutils
    gnugrep
    gnutar
  ];
  text = ''
    export TERMUX_CACHE_DOCKER_CONTEXT=${lib.escapeShellArg dockerContext}
    ${builtins.readFile ./build.sh}
  '';
}
