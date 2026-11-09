{
  lib,
  writeShellApplication,
  curl,
  jq,
  util-linux,
}:
writeShellApplication {
  name = "teams-messages";
  runtimeInputs = [
    curl
    jq
    util-linux # column
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
