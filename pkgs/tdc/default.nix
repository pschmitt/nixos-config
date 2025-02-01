{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication {
  pname = "tdc";
  version = "2025-02-01";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tdc";
    rev = "5d7d114eabf5e77d4b91a07117ab31f401f7fab7";
    hash = "sha256-k1WV0gntS4nr+SLoxLnnwMvy/4Up/YH0eQ3cWdoqvvc=";
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
