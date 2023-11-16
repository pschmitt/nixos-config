{ lib
, python3Packages
, fetchFromGitHub
# build
, setuptools
, setuptools-scm
, wheel
# deps
, fontforge
}:

python3Packages.buildPythonApplication rec {
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

  propagatedBuildInputs = [
    python3Packages.fontforge
  ];

  pythonImportsCheck = [ "font_resizer" ];

  meta = with lib; {
    description = "CLI for controlling OBS Studio";
    homepage = "https://github.com/pschmitt/font-resizer";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "font-resizer";
  };
}
