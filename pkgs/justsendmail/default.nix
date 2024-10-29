{
  lib,
  python3,
  fetchPypi,
  myl-discovery,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "justsendmail";
  version = "3.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-PHfnl81SBufYY58fzy//dGnKCBBfE0szl+amTQ6Bvds=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.setuptools-scm
  ];

  dependencies = [ myl-discovery ];

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
