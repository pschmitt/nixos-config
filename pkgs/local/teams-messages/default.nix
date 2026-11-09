{
  lib,
  stdenv,
  writeShellApplication,
  inputs,
  curl,
  jq,
}:
writeShellApplication {
  name = "teams-messages";
  runtimeInputs = [
    curl
    jq
    inputs.tsvtool.packages.${stdenv.hostPlatform.system}.default
  ];
  text = builtins.readFile ./teams-messages.sh;
  meta = {
    description = "List recent Microsoft Teams messages from the Home Assistant msteams integration";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.unix;
    mainProgram = "teams-messages";
  };
}
