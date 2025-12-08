{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.13.1";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-SsTz4YZ+6TA5GxZZWUC0u+ratN5gA3Gfnajv2pISgNs=";
  };

  npmDepsHash = "sha256-Bgf623Ic4hFgKMmk+hml20LR2MHH8ssL34tprTNZ5KM=";

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
