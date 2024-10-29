{
  lib,
  python3,
  fetchPypi,
  myl-discovery,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "justsendmail";
  version = "4.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-WFkJDGc8sh3QqTSU3ISUOeRXELdAFwNLCj/XRjD1bac=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.setuptools-scm
  ];

  dependencies = [
    myl-discovery
    python3.pkgs.rich
    python3.pkgs.rich-argparse
  ];

  optional-dependencies = with python3.pkgs; {
    dev = [
      black
      mypy
      pyinstaller
    ];
  };

  pythonImportsCheck = [ "justsendmail" ];

  meta = {
    description = "Simple lib to send mail";
    homepage = "https://pypi.org/project/justsendmail";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "justsendmail";
  };
}
