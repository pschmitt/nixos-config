{
  lib,
  python3,
  fetchPypi,
  myl-discovery,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "justsendmail";
  version = "3.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-dr4w0OPGTQbN0V6/19dadF0wKyiSmtcXw4g7q/xF8z4=";
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
