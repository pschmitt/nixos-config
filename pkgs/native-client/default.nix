{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs,
  jq,
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

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/lib/mozilla/native-messaging-hosts $out/lib/chromium/NativeMessagingHosts
    cp $src/config.js $src/follow-redirects.js $src/host.js $src/messaging.js \
      $out/lib/mozilla/native-messaging-hosts
    cp $src/config.js $src/follow-redirects.js $src/host.js $src/messaging.js \
      $out/lib/chromium/NativeMessagingHosts

    BINARY=$out/bin/run.sh
    # Mediator manifests
    get_extension_ids() {
      ${nodejs}/bin/node -e '
        const file = process.argv[1]
        const key = process.argv[2]
        const config = require(file)
        console.log(JSON.stringify(config.ids[key], null, 2))
      ' $src/config.js "$1"
    }

    EXT_FIREFOX=$(get_extension_ids firefox)
    ${jq}/bin/jq -ner \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_FIREFOX" '
      {
        "name": "com.add0n.node",
        "description": "Node Host for Native Messaging",
        "path": $bin,
        "type": "stdio",
        "allowed_extensions": $ext
      }' > $out/lib/mozilla/native-messaging-hosts/com.add0n.node.json

    EXT_CHROME=$(get_extension_ids chrome)
    ${jq}/bin/jq -ner \
      --arg bin "$BINARY" \
      --argjson ext "$EXT_CHROME" '
      {
        "name": "com.add0n.node",
        "description": "Node Host for Native Messaging",
        "path": $bin,
        "type": "stdio",
        "allowed_origins": $ext
      }' > $out/lib/chromium/NativeMessagingHosts/com.add0n.node.json

    mkdir $out/bin
    cat > $BINARY <<EOF
    #!${stdenv.shell}
    ${nodejs}/bin/node $out/lib/mozilla/native-messaging-hosts/host.js "\$@"
    EOF
    chmod +x $BINARY
  '';

  meta = {
    description = "Native Messaging component for Windows, Linux, and Mac OS that is written in NodeJS";
    homepage = "https://github.com/andy-portmen/native-client";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "native-client";
    platforms = lib.platforms.all;
  };
}
