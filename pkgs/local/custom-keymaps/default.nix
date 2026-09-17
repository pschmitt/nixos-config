{
  lib,
  stdenvNoCC,
  ckbcomp,
  xkeyboard_config,
  xkbcomp,
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

      cat > "$out/share/keymaps/custom/${layout}.xkb" <<EOF
      xkb_keymap {
        xkb_keycodes { include "evdev+aliases(qwerty)" };
        xkb_types { include "complete" };
        xkb_compat { include "complete" };
        xkb_symbols { include "pc+${layout}" };
        xkb_geometry { include "pc(pc105)" };
      };
      EOF

      xkbcomp \
        -w 0 \
        -xkb \
        -I"$out/share/X11/xkb" \
        -I"${xkeyboard_config}/share/X11/xkb" \
        "$out/share/keymaps/custom/${layout}.xkb" \
        "$out/share/keymaps/custom/${layout}.compiled.xkb"

      mv "$out/share/keymaps/custom/${layout}.compiled.xkb" \
        "$out/share/keymaps/custom/${layout}.xkb"
    '') layouts
  );
in
stdenvNoCC.mkDerivation {
  pname = "pschmitt-keymaps";
  version = "unstable-2025-11-21";
  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    ckbcomp
    xkbcomp
  ];

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
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
