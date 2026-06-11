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
  pname = "systemctl-service-exec";
  version = "unstable-2025-12-11";

  src = ./systemctl-service-exec.sh;

  phases = [ "installPhase" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 $src $out/bin/systemctl-service-exec

    wrapProgram $out/bin/systemctl-service-exec \
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

  meta = {
    description = "Shell helper to enter a systemd service namespace";
    platforms = lib.platforms.linux;
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "systemctl-service-exec";
  };
}
