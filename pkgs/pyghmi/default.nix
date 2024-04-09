{ lib
, python3
, fetchPypi
}:

python3.pkgs.buildPythonApplication rec {
  pname = "pyghmi";
  version = "1.5.68";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-S8MUaYJFLSorNYRthiI4d7NVx54mL6qfDZgDp+/4pm4=";
  };

  nativeBuildInputs = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  propagatedBuildInputs = with python3.pkgs; [
    cryptography
    python-dateutil
    pbr
    six
  ];

  pythonImportsCheck = [ "pyghmi" ];

  meta = with lib; {
    description = "Python General Hardware Management Initiative (IPMI and others)";
    homepage = "https://pypi.org/project/pyghmi/";
    license = licenses.asl20;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "pyghmi";
  };
}
