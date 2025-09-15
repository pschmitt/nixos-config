{ final, prev }:
{
  brotab = prev.brotab.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ final.jq ];

    postInstall = ''
      mkdir -p $out/lib/mozilla/native-messaging-hosts $out/lib/chromium/NativeMessagingHosts

      # Firefox mediator: only patch the path
      jq --arg out "$out" '.path = "\($out)/bin/bt_mediator"' \
        $out/lib/python3*/site-packages/brotab/mediator/firefox_mediator.json \
        > $out/lib/mozilla/native-messaging-hosts/brotab_mediator.json

      # Chromium mediator: patch the path and add the extra allowed origin
      jq --arg out "$out" --arg ext "knldjmfmopnpolahpmmgbagdohdnhkik" '
        .path = "\($out)/bin/bt_mediator"
        | .allowed_origins = (
            (.allowed_origins // [])
            + ["chrome-extension://\($ext)/"]
          | unique)
      ' \
        $out/lib/python3*/site-packages/brotab/mediator/chromium_mediator.json \
        > $out/lib/chromium/NativeMessagingHosts/brotab_mediator.json
    '';
  });
}
