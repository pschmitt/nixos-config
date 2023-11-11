{ lib
, python3Packages
, fetchPypi
}:

python3Packages.buildPythonApplication rec {
  pname = "ldifj";
  version = "0.1.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-UgMR6xOxA1IEy1YdrX8dnzJE0KPitDXxTcl/rqioHfE=";
  };

  nativeBuildInputs = [
    python3Packages.setuptools
    python3Packages.setuptools-scm
    python3Packages.wheel
  ];

  propagatedBuildInputs = [
    python3Packages.python-ldap
    python3Packages.rich
    python3Packages.rich-argparse
  ];

  meta = with lib; {
    description = "Convert LDIF to JSON";
    homepage = "https://github.com/pschmitt/ldifj";
    license = licenses.gpl3;
    maintainers = with maintainers; [ pschmitt ];
  };
}
