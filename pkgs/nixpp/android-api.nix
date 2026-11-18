{
  callPackage,
  coreutils,
  inputs,
  lib,
  symlinkJoin,
  writeShellApplication,
}:
let
  source = inputs.droid-nix-src + "/pkgs/android-integration";
  androidApp = {
    packageName = "dev.pschmitt.termux";
    dataDir = "/android/data/data/dev.pschmitt.termux";
  };
  # TermuxPP already runs the upstream TermuxAm socket server. Droid-nix uses
  # the same protocol but places the socket directly under its files directory.
  termux-am = (callPackage (source + "/termux-am.nix") { inherit androidApp; }).overrideAttrs (old: {
    postPatch = old.postPatch + ''
      substituteInPlace termux-am.h \
        --replace-fail /files/am.sock /files/apps/dev.pschmitt.termux/termux-am/am.sock
    '';
  });
  androidPath = lib.getExe (writeShellApplication {
    name = "nixpp-android-path";
    runtimeInputs = [ coreutils ];
    text = builtins.readFile ./scripts/android-api-path.sh;
  });
  api =
    (callPackage (source + "/termux-api.nix") { inherit androidApp termux-am; }).overrideAttrs
      (old: {
        postPatch = old.postPatch + ''
          substituteInPlace termux-api.c \
            --replace-fail com.termux.api.TermuxApiReceiver dev.pschmitt.termux.api.TermuxApiReceiver
          substituteInPlace scripts/termux-api-start.in scripts/termux-api-stop.in \
            --replace-fail com.termux.api.KeepAliveService dev.pschmitt.termux.api.KeepAliveService

          substituteInPlace scripts/termux-{keystore,media-player,media-scan,microphone-record,share,storage-get,wallpaper}.in \
            --replace-fail realpath '${androidPath}'
          substituteInPlace scripts/termux-camera-photo.in \
            --replace-fail 'PARAMS="$PARAMS --es file `realpath $1`"' 'file=$(${androidPath} "$1") || exit 1' \
            --replace-fail 'CameraPhoto $PARAMS' 'CameraPhoto $PARAMS --es file "$file"'
          substituteInPlace scripts/termux-download.in \
            --replace-fail 'OPT_P="$OPTARG"' 'OPT_P=$(${androidPath} "$OPTARG") || exit 1'
          substituteInPlace scripts/termux-notification.in \
            --replace-fail 'OPT_IMAGE_PATH="$2"' 'OPT_IMAGE_PATH=$(${androidPath} "$2") || exit 1'
        '';
      });
in
symlinkJoin {
  name = "termuxpp-api";
  paths = [ api ];
  postBuild = ''
    for command in "$out"/bin/droid-nix-*; do
      name=''${command##*/}
      ln -s -- "$name" "$out/bin/termux-''${name#droid-nix-}"
    done
  '';
  meta = {
    description = "TermuxPP Android API commands for the managed Linux guest";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.mit;
  };
}
