{
  lib,
  python3,
  fetchPypi,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "myl-discovery";
  version = "0.6.1";
  pyproject = true;

  src = fetchPypi {
    pname = "myl_discovery";
    inherit version;
    hash = "sha256-5ulMzqd9YovEYCKO/B2nLTEvJC+bW76pJtDu1cNXLII=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.setuptools-scm
  ];

  dependencies = with python3.pkgs; [
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
    mainProgram = "myl-discovery";
  };
}
