{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication {
  pname = "tdc";
  version = "2025-02-02";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tdc";
    rev = "22e311d64b2c7780f3652259ee273cca4805ef2b";
    hash = "sha256-N+SqV/NX7J9Qk7rgu1lxNnNNK8qYjwF0BONFWUEpzmI=";
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
