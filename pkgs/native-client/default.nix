{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  jq,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "native-client";
  version = "1.0.8";

  src = fetchFromGitHub {
    owner = "andy-portmen";
    repo = "native-client";
    rev = "v${version}";
    hash = "sha256-/Zr5FSfZ5Sh1kE/x0wF0Uljg0mnE0QkO6etgopaIXmo=";
  };

  nativeBuildInputs = [
    jq
    nodejs
    makeWrapper
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    # code
    hostDir=$out/libexec/native-client
    firefoxHosts=$out/lib/mozilla/native-messaging-hosts
    chromeHosts=$out/lib/chromium/NativeMessagingHosts

    mkdir -p "$hostDir" "$firefoxHosts" "$chromeHosts"
    # Keep manifests clean; only manifests live in native-messaging-hosts.
    install -Dm444 -t "$hostDir" \
      $src/config.js \
      $src/host.js \
      $src/messaging.js

    APP_NAME="com.add0n.node"
    APP_DESCRIPTION="Node Host for Native Messaging"
    BINARY=$out/bin/run.sh

    # Mediator manifests
    get_extension_ids() {
      node -e '
        const file = process.argv[1]
        const key = process.argv[2]
        const config = require(file)
        console.log(JSON.stringify(config.ids[key], null, 2))
      ' "$hostDir/config.js" "$1"
    }

    EXT_FIREFOX=$(get_extension_ids firefox)
    jq -ner \
      --arg name "$APP_NAME" \
      --arg description "$APP_DESCRIPTION" \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_FIREFOX" '
      {
        "name": $name,
        "description": $description,
        "path": $bin,
        "type": "stdio",
        "allowed_extensions": $ext
      }' > "$firefoxHosts/$APP_NAME.json"

    EXT_CHROME=$(get_extension_ids chrome)
    jq -ner \
      --arg name "$APP_NAME" \
      --arg description "$APP_DESCRIPTION" \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_CHROME" '
      {
        "name": $name,
        "description": $description,
        "path": $bin,
        "type": "stdio",
        "allowed_origins": ($ext | map("chrome-extension://" + . + "/"))
      }' > "$chromeHosts/$APP_NAME.json"

    makeWrapper ${nodejs}/bin/node "$BINARY" \
      --add-flags "$hostDir/host.js"
  '';

  meta = {
    description = "Native Messaging component for Windows, Linux, and Mac OS that is written in NodeJS";
    homepage = "https://github.com/andy-portmen/native-client";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    # mainProgram = "run.sh";
    platforms = lib.platforms.all;
  };
}
