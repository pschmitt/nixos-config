# Monit-style check: exit non-zero when a Mullvad account is inactive or
# expires within the warning window.
{
  lib,
  writeShellApplication,
  coreutils,
  curl,
  jq,
}:
writeShellApplication {
  name = "mullvad-expiration";
  runtimeInputs = [
    coreutils
    curl
    jq
  ];
  text = builtins.readFile ./mullvad-expiration.sh;
  meta = {
    description = "Check a Mullvad account's remaining time";
    platforms = lib.platforms.linux;
    mainProgram = "mullvad-expiration";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
