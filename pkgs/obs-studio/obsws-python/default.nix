{
  lib,
  buildPythonPackage,
  fetchPypi,
  # build-system
  hatchling,
  # dependencies
  tomli,
  websocket-client,
}:

buildPythonPackage rec {
  pname = "obsws-python";
  version = "1.6.2";
  pyproject = true;

  src = fetchPypi {
    inherit version;
    pname = "obsws_python";
    hash = "sha256-cR1gnZ5FxZ76SD9GlHSIhv142ejsqs/Bp8wV1A1kfdw=";
  };

  nativeBuildInputs = [ hatchling ];

  propagatedBuildInputs = [
    tomli
    websocket-client
  ];

  doCheck = false;

  meta = with lib; {
    description = "A Python SDK for OBS Studio WebSocket v5.0";
    homepage = "https://github.com/aatikturk/obsws-python";
    license = licenses.gpl3;
    maintainers = with maintainers; [ pschmitt ];
  };
}
