{
  lib,
  stdenvNoCC,
  timew-status,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-timewarrior";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.toml
      ./service.luau
      ./bar.luau
      ./panel.luau
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/noctalia-plugins/timewarrior
    mkdir -p "$dest"

    cp plugin.toml bar.luau panel.luau "$dest"/
    substitute service.luau "$dest"/service.luau \
      --subst-var-by timewIsOn ${timew-status}/bin/timew-is-on \
      --subst-var-by timewTotal ${timew-status}/bin/timew-total \
      --subst-var-by timewWeekBreakdown ${timew-status}/bin/timew-week-breakdown

    runHook postInstall
  '';

  meta = {
    description = "Timewarrior tracked-time bar widget for Noctalia, ported from the DMS/Waybar module";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
