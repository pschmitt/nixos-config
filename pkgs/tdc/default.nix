{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication {
  pname = "tdc";
  version = "2025-02-05";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tdc";
    rev = "ee306841deaaa9cfdfc38e9abf73becd0b427762";
    hash = "sha256-+nLh1FNBpWDZRHHa/6ZO525lsh+OiiL34cPVX8+8Vxo=";
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
