_finalPy: prevPy: {
  # Nixpkgs' pname differs from upstream's distribution metadata name.
  # Retained pending checks against top-level Nixpkgs 1d060086d60cb76a40cf37109f979d88a5bd6396.
  python-aodhclient = prevPy.python-aodhclient.overridePythonAttrs (_: {
    dontCheckPythonMetadata = true;
  });
}
