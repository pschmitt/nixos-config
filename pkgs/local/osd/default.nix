# Simple CLI for firing ad-hoc OSDs/toasts through Noctalia, falling back to
# notify-send/mako when the graphical session is unavailable.
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
    description = "Fire an ad-hoc OSD/toast via Noctalia (falls back to notify-send/mako)";
    platforms = lib.platforms.linux;
    mainProgram = "osd";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
