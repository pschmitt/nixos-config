{
  lib,
  buildPythonApplication,
  fetchFromGitHub,
  # build
  setuptools,
  setuptools-scm,
  wheel,
  fontforge,
}:

buildPythonApplication rec {
  pname = "font-resizer";
  version = "0.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = pname;
    rev = version;
    hash = "sha256-ZZpIS45UNJm5xsJuxgEdsmh2Fuga20QH/YNCaDrufJ0=";
  };

  nativeBuildInputs = [
    setuptools
    setuptools-scm
    wheel
  ];

  propagatedBuildInputs = [ fontforge ];

  pythonImportsCheck = [ "font_resizer" ];

  meta = {
    description = "CLI for controlling OBS Studio";
    homepage = "https://github.com/pschmitt/font-resizer";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "font-resizer";
  };
}
