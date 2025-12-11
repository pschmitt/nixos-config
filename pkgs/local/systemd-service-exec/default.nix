{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  makeWrapper,
  sudo,
  systemd,
  util-linux,
}:

stdenvNoCC.mkDerivation {
  pname = "systemd-service-exec";
  version = "unstable-2025-12-11";

  src = ./systemd-service-exec.sh;

  phases = [ "installPhase" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 $src $out/bin/systemd-service-exec

    wrapProgram $out/bin/systemd-service-exec \
      --prefix PATH : "/run/wrappers/bin:${
        lib.makeBinPath [
          bash
          coreutils
          sudo
          systemd
          util-linux
        ]
      }"
  '';

  meta = with lib; {
    description = "Shell helper to enter a systemd service namespace";
    platforms = platforms.linux;
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "systemd-service-exec";
  };
}
