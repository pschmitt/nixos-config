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
    rev = "ae9a66503eec6359f0e867f0ec4065260d59f284";
    hash = "sha256-jmk4+7FPhW6Cjjnp4pIEky7JVZjgwTugZ9ls4BewhtE=";
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
