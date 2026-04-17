{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.14.0";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-laA7bU47P6ZzFkO2ubheSYIlMs07Gh3ZtBC2emXlz1M=";
  };

  npmDepsHash = "sha256-2KyONy6GUatO9sw1Yq1hYbQx6gNnZxVBkYPnp35aTT0=";

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
