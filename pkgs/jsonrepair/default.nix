{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.14.1";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-jP9mOS6m5gP3uIQatui01jeIi1kLFZiZh/eCzr/tSgI=";
  };

  npmDepsHash = "sha256-dhEmxiA9pYqFBbTbtvxM618bUiVW9Xrr9etErz58S70=";

  # The prepack script runs the build script, which we'd rather do in the build phase.
  # npmPackFlags = [ "--ignore-scripts" ];

  # NODE_OPTIONS = "--openssl-legacy-provider";

  meta = {
    description = "Repair invalid JSON documents";
    homepage = "https://josdejong.github.io/jsonrepair/";
    license = lib.licenses.isc;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "jsonrepair";
  };
}
