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
  version = "0.9.8";

  src = fetchFromGitHub {
    owner = "andy-portmen";
    repo = "native-client";
    rev = version;
    hash = "sha256-g+X4TaOjw/cBxQP/mA2cBFya3DubQMJAortxHhs/hWc=";
  };

  nativeBuildInputs = [
    jq
    nodejs
    makeWrapper
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    # code
    mkdir -p $out/lib/mozilla/native-messaging-hosts $out/lib/chromium/NativeMessagingHosts
    cp $src/config.js $src/follow-redirects.js $src/host.js $src/messaging.js \
      $out/lib/mozilla/native-messaging-hosts
    cp $src/config.js $src/follow-redirects.js $src/host.js $src/messaging.js \
      $out/lib/chromium/NativeMessagingHosts

    APP_NAME="com.add0n.node"
    BINARY=$out/bin/run.sh

    # Mediator manifests
    get_extension_ids() {
      node -e '
        const file = process.argv[1]
        const key = process.argv[2]
        const config = require(file)
        console.log(JSON.stringify(config.ids[key], null, 2))
      ' $src/config.js "$1"
    }

    EXT_FIREFOX=$(get_extension_ids firefox)
    jq -ner \
      --arg name "$APP_NAME" \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_FIREFOX" '
      {
        "name": $name,
        "description": "Node Host for Native Messaging",
        "path": $bin,
        "type": "stdio",
        "allowed_extensions": $ext
      }' > "$out/lib/mozilla/native-messaging-hosts/$APP_NAME.json"

    EXT_CHROME=$(get_extension_ids chrome)
    jq -ner \
      --arg name "$APP_NAME" \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_CHROME" '
      {
        "name": $name,
        "description": "Node Host for Native Messaging",
        "path": $bin,
        "type": "stdio",
        "allowed_origins": $ext
      }' > "$out/lib/chromium/NativeMessagingHosts/$APP_NAME.json"

    makeWrapper ${nodejs}/bin/node "$BINARY" \
      --add-flags $out/lib/mozilla/native-messaging-hosts/host.js
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
