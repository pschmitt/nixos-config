{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  dnspython,
  exchangelib,
  requests,
  rich,
  xmltodict,
}:

buildPythonPackage rec {
  pname = "myl-discovery";
  version = "0.5.9";
  pyproject = true;

  src = fetchPypi {
    pname = "myl_discovery";
    inherit version;
    hash = "sha256-NECQAREDeYsUy37jsyU0NPPy1smBneZ0E+mufNBkBFc=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    dnspython
    exchangelib
    requests
    rich
    xmltodict
  ];

  pythonImportsCheck = [ "myldiscovery" ];

  meta = {
    description = "Email autodiscovery";
    homepage = "https://pypi.org/project/myl-discovery/";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}
