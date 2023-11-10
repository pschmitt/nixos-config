{ lib, buildNpmPackage, fetchFromGitHub }:

buildNpmPackage rec {
  pname = "jsonrepair";
  version = "3.4.0";

  src = fetchFromGitHub {
    owner = "josdejong";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-E7ilA+Rqq1zj2Qusr9RpDsxq6Um9VAv/2T0fwhOKsbM=";
  };

  npmDepsHash = "sha256-kvKjqmr4LodnIz+QNcf/fmzZ2SqB3msI41UBg0Rc2XQ=";

  # The prepack script runs the build script, which we'd rather do in the build phase.
  # npmPackFlags = [ "--ignore-scripts" ];

  # NODE_OPTIONS = "--openssl-legacy-provider";

  meta = with lib; {
    description = "Repair invalid JSON documents";
    homepage = "https://josdejong.github.io/jsonrepair/";
    license = licenses.isc;
    maintainers = with maintainers; [ pschmitt ];
  };
}
