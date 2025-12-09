{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  procps,
  socat,
  netcat-openbsd,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hyprevents";
  version = "0-unstable-2024-10-15";

  src = fetchFromGitHub {
    owner = "vilari-mickopf";
    repo = "hyprevents";
    rev = "d4397df0f04da244f58fc7f6e4d8a01ec9200cc0";
    hash = "sha256-Amfv7Kh+oWc3IDZih6E5sU8gqc3gOZdDbr8B67LjkYU=";
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 hyprevents $out/libexec/hyprevents/hyprevents
    install -Dm755 event_loader $out/libexec/hyprevents/event_loader
    install -Dm755 event_handler $out/libexec/hyprevents/event_handler

    runHook postInstall
  '';

  postInstall = ''
    patchShebangs $out/libexec/hyprevents

    makeWrapper $out/libexec/hyprevents/hyprevents $out/bin/hyprevents \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          findutils
          procps
          socat
          netcat-openbsd
        ]
      }
  '';

  meta = with lib; {
    description = "Hyprland event loader shim and helper scripts";
    homepage = "https://github.com/vilari-mickopf/hyprevents";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "hyprevents";
  };
})
