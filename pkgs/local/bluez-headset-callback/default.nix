{
  lib,
  makeWrapper,
  stdenvNoCC,
  bash,
  gnused,
  jq,
  libnotify,
  systemd,
  zsh,
}:

stdenvNoCC.mkDerivation {
  pname = "bluez-headset-callback";
  version = "0.6";

  src = ./bluez-headset-callback.sh;

  phases = [ "installPhase" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm 755 $src $out/bin/bluez-headset-callback.sh

    wrapProgram $out/bin/bluez-headset-callback.sh \
      --prefix PATH : "/run/wrappers/bin:${
        lib.makeBinPath [
          bash
          gnused
          jq
          libnotify
          systemd
          zsh
        ]
      }"
  '';

  meta = with lib; {
    description = "custom bluez dbus listener for headset setup";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "bluez-headset-callback.sh";
  };
}
