# Mute / volume-step helper for the ARD, ZDF and Tagesschau OBS sources.
# Companion of home-manager/gui/obs-broadcast-audio.lua (same allowlist).
{
  lib,
  python3,
  runCommand,
  writeShellApplication,
}:
let
  python = python3.withPackages (ps: [ ps.obsws-python ]);
in
writeShellApplication {
  name = "obs-tv-audio";
  text = ''
    exec ${python}/bin/python3 ${./obs-tv-audio.py} "$@"
  '';
  passthru.tests.unit =
    runCommand "obs-tv-audio-unit-test"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        cp ${./obs-tv-audio.py} obs-tv-audio.py
        cp ${./test_obs_tv_audio.py} test_obs_tv_audio.py
        python3 -I test_obs_tv_audio.py
        touch $out
      '';
  meta = {
    description = "Mute or step the volume of the active ARD/ZDF/Tagesschau OBS source";
    platforms = lib.platforms.linux;
    mainProgram = "obs-tv-audio";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
