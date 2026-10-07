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
    pname = "termux-apt-prefix-builder-docker-context";
    version = "1";
    src = lib.cleanSource ./.;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp prepare-termux-prefix.sh "$out/"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "termux-apt-prefix-builder";
  runtimeInputs = [
    coreutils
    docker-client
    file
    findutils
    gnugrep
    gnutar
  ];
  text = ''
    export TERMUX_PREFIX_BUILDER_CONTEXT=${lib.escapeShellArg dockerContext}
    ${builtins.readFile ./build.sh}
  '';
}
