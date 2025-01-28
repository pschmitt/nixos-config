{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication {
  pname = "tdc";
  version = "unstable-2025-01-27";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tdc";
    rev = "63370ff84f1eb333054593e326f42df2ede12388";
    hash = "sha256-sfmSW51w6PHkSdpWy6j3YNU//EpB+fKAz9H37EKZFRU=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  dependencies = with python3.pkgs; [
    rich-argparse
    todoist-api-python
  ];

  pythonImportsCheck = [
    "tdc"
  ];

  meta = {
    description = "Todoist CLI, powered by rich";
    homepage = "https://github.com/pschmitt/tdc";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tdc";
  };
}
