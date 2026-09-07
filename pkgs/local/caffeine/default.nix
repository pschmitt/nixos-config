# Simple CLI for toggling and controlling Noctalia's idle inhibitor (caffeine).
{
  lib,
  writeShellApplication,
  systemd,
  jq,
  coreutils,
  noctalia ? null,
}:
writeShellApplication {
  name = "caffeine";
  runtimeInputs = [
    systemd
    jq
    coreutils
  ]
  ++ lib.optional (noctalia != null) noctalia;
  text = builtins.readFile ./caffeine.sh;
  meta = {
    description = "Control Noctalia's idle inhibitor (caffeine)";
    platforms = lib.platforms.linux;
    mainProgram = "caffeine";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
