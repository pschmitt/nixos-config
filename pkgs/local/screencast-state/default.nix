# Single source of truth for "is something screencasting, and what?", read
# straight from the PipeWire graph. Shared by the quickshell-bar and waybar
# screencast indicators and the go-hass-agent screencast sensor, all of which
# used to read /tmp/screencast.json written by the (now disabled)
# xdg-portal-screencast-watcher service.
{
  lib,
  writeShellApplication,
  pipewire,
  jq,
}:
writeShellApplication {
  name = "screencast-state";
  runtimeInputs = [
    pipewire # pw-dump
    jq
  ];
  text = builtins.readFile ./screencast-state.sh;
  meta = {
    description = "Report live xdg-desktop-portal screencasts from the PipeWire graph";
    platforms = lib.platforms.linux;
    mainProgram = "screencast-state";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
