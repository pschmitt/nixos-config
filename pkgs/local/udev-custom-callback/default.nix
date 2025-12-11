{
  lib,
  makeWrapper,
  stdenvNoCC,
  bash,
  shadow,
  systemd,
}:

stdenvNoCC.mkDerivation {
  pname = "udev-custom-callback";
  version = "0.3";

  src = ./udev-custom-callback.sh;
  # rules = ./99-custom-bluetooth.rules;

  phases = [ "installPhase" ];

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    bash
    shadow
    systemd
  ];

  installPhase = ''
    install -Dm 755 $src $out/bin/udev-custom-callback.sh
    # install -D $rules $out/lib/udev/rules.d/99-custom-bluetooth.rules

    wrapProgram $out/bin/udev-custom-callback.sh \
      --prefix PATH : "${
        lib.makeBinPath [
          bash
          shadow.su
          systemd
        ]
      }"
  '';

  meta = with lib; {
    description = "custom udev callback";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    platforms = platforms.linux;
  };
}
