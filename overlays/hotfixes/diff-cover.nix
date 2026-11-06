_pyfinal: pyprev: {
  # Pygments HTML escaping changes break these snapshots. Retained pending
  # checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  diff-cover = pyprev.diff-cover.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      "test_added_file_pycodestyle_html"
      "test_all_reports"
      "test_added_file_pyflakes_html"
      "test_added_file_pylint_html"
      "test_fail_under_html"
      "test_fail_under_pass_html"
    ];
  });
}
