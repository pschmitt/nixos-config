{
  lib,
  writers,
  libnotify,
  wl-clipboard,
  xdg-utils,
}:
(writers.writePython3Bin "ha-walker" {
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      libnotify
      wl-clipboard
      xdg-utils
    ])
  ];
} (builtins.readFile ./ha_walker.py)).overrideAttrs
  (_old: {
    meta = {
      description = "Home Assistant helper for Walker menu";
      license = lib.licenses.gpl3Only;
      maintainers = with lib.maintainers; [ pschmitt ];
      platforms = lib.platforms.linux;
      mainProgram = "ha-walker";
    };
  })
