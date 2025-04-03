{
  lib,
  fetchPypi,
  buildPythonApplication,
  # build
  setuptools,
  setuptools-scm,
  wheel,
  # deps
  obsws-python,
  rich,
}:

buildPythonApplication rec {
  pname = "obs-cli";
  version = "0.6.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-lAzNI1a7aJsbtwD/XHn6KjKHBAWByRBINAe6h8qUeHE=";
  };

  nativeBuildInputs = [
    setuptools
    setuptools-scm
    wheel
  ];

  propagatedBuildInputs = [
    obsws-python
    rich
  ];

  pythonImportsCheck = [ "obs_cli" ];

  meta = with lib; {
    description = "CLI for controlling OBS Studio";
    homepage = "https://github.com/pschmitt/obs-cli";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "obs-cli";
  };
}
