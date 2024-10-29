{
  lib,
  python3,
  fetchPypi,
  myl-discovery,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "myl";
  version = "0.8.9";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-U0nbkobAkn6wBwxvKDo/9Xwu1CLaD5jB0kzEJHNJ0r8=";
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
