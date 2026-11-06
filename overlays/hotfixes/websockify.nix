_pyfinal: pyprev: {
  # Fixture HS256 keys fail jwcrypto's 256-bit minimum. Retained pending
  # checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  websockify = pyprev.websockify.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      "test_symmetric_jws_token_plugin"
      "test_symmetric_jws_token_plugin_with_illigal_key_exception"
    ];
  });
}
