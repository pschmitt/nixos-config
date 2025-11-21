{
  lib,
  stdenvNoCC,
  ckbcomp,
  xkeyboard_config,
}:
let
  symbolsDir = ./symbols;
  layouts = [
    "hhkb-de"
    "gpdpocket4-de"
    "gpdpocket4-us"
  ];
  layoutCommands = lib.concatStringsSep "\n" (
    map (layout: ''
      install -Dm644 "${symbolsDir}/${layout}" \
        "$out/share/X11/xkb/symbols/${layout}"

      ckbcomp \
        -I"${symbolsDir}" \
        -I"${xkeyboard_config}/share/X11/xkb" \
        -layout "${layout}" \
        > "$out/share/keymaps/custom/${layout}.map"
    '') layouts
  );
in
stdenvNoCC.mkDerivation {
  pname = "pschmitt-keymaps";
  version = "unstable-2025-11-21";
  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [ ckbcomp ];

  installPhase = ''
    runHook preInstall
    install -dm755 "$out/share/X11/xkb/symbols" "$out/share/keymaps/custom"
  ''
  + layoutCommands
  + ''
    runHook postInstall
  '';

  meta = {
    description = "Custom HHKB and GPD Pocket 4 keymaps for XKB and the Linux console";
    platforms = lib.platforms.linux;
  };
}
