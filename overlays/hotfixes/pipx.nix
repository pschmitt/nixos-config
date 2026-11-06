_finalPy: prevPy: {
  # Python 3.13 expectations and test collection workarounds from the prior
  # baseline; retain pending checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  pipx = prevPy.pipx.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      "test_fix_package_name"
      "test_parse_specifier_for_metadata"
    ];
    disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "tests/test_inject.py" ];
  });
}
