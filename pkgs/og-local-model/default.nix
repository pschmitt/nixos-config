{
  lib,
  fetchurl,
  runCommand,
}:

let
  # The detector og-local runs in-process. Pinned to one HuggingFace revision;
  # bump the revision and the hashes together (`ogl model pull` prints the files).
  # renovate: datasource=git-refs depName=https://huggingface.co/openai/privacy-filter
  revision = "7ffa9a043d54d1be65afb281eddf0ffbe629385b";

  files = {
    "onnx/model_q4f16.onnx" = "sha256-6q5Og88TRaYKvjM+2IK1X+V3XR3780ubJp5eVBb0Xls=";
    "onnx/model_q4f16.onnx_data" = "sha256-bU3eeH4DrOKDxF1OMqlO7DK2z8wkLnIZvqlvW0wTVp0=";
    "tokenizer.json" = "sha256-BhT+g8ratCEpbmZOH0j0Jh+o/vbgPmO7dcIPOON9B9M=";
    "tokenizer_config.json" = "sha256-bBSvnOGihNPDxRRrJu/kzVicaOHdTp2URVYG7JEbp3Q=";
    "config.json" = "sha256-srJqSkoABjmtMLDCZK2+/jZb21Z/vXuycwO4xDg3W9E=";
    "viterbi_calibration.json" = "sha256-u8hhHvCKVe1y1khWy7u5qR2436iB8KkuKvutbku8d1o=";
  };

  fetched = lib.mapAttrs (
    name: hash:
    fetchurl {
      url = "https://huggingface.co/openai/privacy-filter/resolve/${revision}/${name}";
      inherit hash;
    }
  ) files;

  manifest = builtins.toJSON {
    name = "openai/privacy-filter";
    inherit revision;
    files = builtins.attrNames files;
  };
in
# Same layout `ogl model pull` creates, for use as OGL_CACHE_DIR.
runCommand "og-local-model-${builtins.substring 0 8 revision}" { inherit manifest; } ''
  dir=$out/models/models--openai--privacy-filter/snapshots/${revision}
  mkdir -p $dir/onnx
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: "ln -s ${src} $dir/${name}") fetched)}
  printf '%s' "$manifest" > $dir/.ogl-manifest.json
''
