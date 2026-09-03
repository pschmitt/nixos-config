# Simple CLI for firing ad-hoc OSDs/toasts — native DMS toast IPC when
# dms.service is the active bar, falling back to notify-send/mako otherwise.
{
  lib,
  writeShellApplication,
  libnotify,
  jq,
}:
writeShellApplication {
  name = "osd";
  runtimeInputs = [
    libnotify # notify-send (fallback)
    jq # mako notification lookup (fallback dismiss)
  ];
  text = builtins.readFile ./osd.sh;
  meta = {
    description = "Fire an ad-hoc OSD/toast via DMS's native toast IPC (falls back to notify-send/mako)";
    platforms = lib.platforms.linux;
    mainProgram = "osd";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
