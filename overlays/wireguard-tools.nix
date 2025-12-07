{ final, prev }:

{
  wireguard-tools = prev.wireguard-tools.overrideAttrs (oldAttrs: {
    postInstall = oldAttrs.postInstall or "" + ''
      # Add wg-json script to the output
      cp $src/contrib/json/wg-json $out/bin/
      chmod +x $out/bin/wg-json
    '';

    postFixup = ''
      # Replace "wg" with the full path to the wg binary in wg-json
      substituteInPlace $out/bin/wg-json \
        --replace "wg show" "$out/bin/wg show"
    ''
    + (oldAttrs.postFixup or "");
  });
}
