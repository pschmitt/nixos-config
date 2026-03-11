{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.13.3";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-hJTM4bDdjQ0OI8Rymc2VNQuOxpslhAIe+EqfptFmpWw=";
  };

  npmDepsHash = "sha256-LmyT/7CocVMK3VEkSzAP6lhqMZVcJBk2vquvnFHbVXw=";

  # The prepack script runs the build script, which we'd rather do in the build phase.
  # npmPackFlags = [ "--ignore-scripts" ];

  # NODE_OPTIONS = "--openssl-legacy-provider";

  meta = with lib; {
    description = "Repair invalid JSON documents";
    homepage = "https://josdejong.github.io/jsonrepair/";
    license = licenses.isc;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "jsonrepair";
  };
}
