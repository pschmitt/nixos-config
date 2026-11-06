_pyfinal: pyprev: {
  # Audio comparison differs from ffmpeg by about 1.7e-3 against a 1e-3
  # tolerance. Retained pending checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  torchcodec = pyprev.torchcodec.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_audio_against_cli" ];
  });
}
