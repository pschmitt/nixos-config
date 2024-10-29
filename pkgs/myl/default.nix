{
  lib,
  python3,
  fetchPypi,
  myl-discovery,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "myl";
  version = "0.8.11";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-DVVRTFAOEcB6zftKBK1WZNsXz7JAk82aBAYGHmvE4Go=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.setuptools-scm
  ];

  dependencies = with python3.pkgs; [
    imap-tools
    myl-discovery
    rich
  ];

  pythonImportsCheck = [ "myl" ];

  meta = {
    description = "Dead simple IMAP CLI client";
    homepage = "https://pypi.org/project/myl/";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "myl";
  };
}
