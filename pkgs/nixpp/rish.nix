{ lib, writeShellApplication }:
let
  nativeScript = ./scripts/rish-native.sh;
in
writeShellApplication {
  name = "rish";
  text = ''
    exec nixpp enter --outer -- /system/bin/sh -c "$(<${nativeScript})" rish "$@"
  '';
  meta = {
    description = "Shizuku shell for managed TermuxPP sessions";
    mainProgram = "rish";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.mit;
  };
}
