{ final, prev }:
{
  brotab = prev.brotab.overrideAttrs (oldAttrs: {
    postInstall = ''
      mkdir -p $out/lib/mozilla/native-messaging-hosts
      sed -r "s#(\"path\":).*#\1 \"$out/bin/bt_mediator\",#" $out/lib/python3*/site-packages/brotab/mediator/firefox_mediator.json > $out/lib/mozilla/native-messaging-hosts/brotab_mediator.json
    '';
  });
}
