{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.13.2";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-4qB0xIVUacrnfoFSSxidm+X+cjp9DPr7+LjOE8Na3Oc=";
  };

  npmDepsHash = "sha256-HVa/As9pD49rD6es/Si+fy/hRUdInjd8DELk386VZvM=";

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
