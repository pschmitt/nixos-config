{
  callPackage,
  coreutils,
  inputs,
  lib,
  python3,
  runCommand,
  symlinkJoin,
  writeShellApplication,
  notificationTimeouts ? {
    low = 4000;
    normal = 7000;
    critical = 15000;
  },
}:
let
  source = inputs.droid-nix-src + "/pkgs/android-integration";
  androidApp = {
    packageName = "dev.pschmitt.termux";
    dataDir = "/android/data/data/dev.pschmitt.termux";
  };
  prefix = "${androidApp.dataDir}/files/usr";
  session = writeShellApplication {
    name = "termuxpp-session";
    text = ''
      script=${prefix}/bin/termuxpp-session
      if [[ ! -r "$script" ]]
      then
        printf '%s\n' 'Open an updated TermuxPP app to install the session CLI.' >&2
        exit 1
      fi
      exec ${lib.getExe python3} "$script" "$@"
    '';
  };
  reloadSettings = writeShellApplication {
    name = "termuxpp-reload-settings";
    text = ''
      exec ${lib.getExe session} reload-settings "$@"
    '';
  };
  notifySend = writeShellApplication {
    name = "notify-send";
    text = ''
      export TERMUXPP_NOTIFICATION_API=${api}/libexec/droid-nix-api
      export TERMUXPP_ANDROID_PATH=${androidPath}
      export TERMUXPP_NOTIFY_TIMEOUTS=${lib.escapeShellArg (builtins.toJSON notificationTimeouts)}
      exec ${lib.getExe python3} ${./scripts/notify-send.py} "$@"
    '';
  };
  sessionCompletions = runCommand "termuxpp-session-completions" { } ''
    mkdir -p "$out/share/bash-completion/completions" \
      "$out/share/fish/vendor_completions.d" "$out/share/zsh/site-functions"
    cat > "$out/share/bash-completion/completions/termuxpp-session" <<'BASH'
    file=${prefix}/share/bash-completion/completions/termuxpp-session
    if [[ -r "$file" ]]
    then
      source "$file"
    fi
    unset file
    BASH
    cat > "$out/share/fish/vendor_completions.d/termuxpp-session.fish" <<'FISH'
    set -l file ${prefix}/share/fish/vendor_completions.d/termuxpp-session.fish
    if test -r "$file"
      source "$file"
    end
    FISH
    cat > "$out/share/zsh/site-functions/_termuxpp-session" <<'ZSH'
    #compdef termuxpp-session
    local file=${prefix}/share/zsh/site-functions/_termuxpp-session
    if [[ -r "$file" ]]
    then
      source "$file"
    fi
    ZSH
  '';
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
  openTools =
    (callPackage (source + "/termux-tools.nix") { inherit androidApp termux-am; }).overrideAttrs
      (old: {
        postPatch = old.postPatch + ''
          substituteInPlace scripts/termux-open.in \
            --replace-fail '${androidApp.packageName}/${androidApp.packageName}.OpenReceiver' '${androidApp.packageName}/com.termux.app.TermuxOpenReceiver' \
            --replace-fail 'realpath "$FILE"' '${androidPath} "$FILE"'
        '';
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
  paths = [
    api
    session
    reloadSettings
    notifySend
    openTools.xdg_open
    sessionCompletions
  ];
  postBuild = ''
    ln -s ${openTools.open}/bin/droid-nix-open "$out/bin/termux-open"
    ln -s termuxpp-reload-settings "$out/bin/termux-reload-settings"
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
