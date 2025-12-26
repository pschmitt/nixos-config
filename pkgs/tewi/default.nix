{
  lib,
  python3,
  fetchFromGitHub,
  fetchPypi,
}:

let
  geoip2fast = python3.pkgs.buildPythonPackage rec {
    pname = "geoip2fast";
    version = "1.2.2";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-OIFXAM7f6xl9UbS4czsNT3lls23hUUfBJVJxJPi0XWs=";
    };

    build-system = [
      python3.pkgs.setuptools
    ];

    pythonImportsCheck = [
      "geoip2fast"
    ];
  };
in
python3.pkgs.buildPythonApplication rec {
  pname = "tewi";
  version = "2.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "anlar";
    repo = "tewi";
    rev = "v${version}";
    hash = "sha256-XLriHazE+YyLTEWcjDuW+3WX3NKYdsvzRmIc/Oc81oM=";
  };

  build-system = [
    python3.pkgs.setuptools
  ];

  dependencies = with python3.pkgs; [
    geoip2fast
    platformdirs
    pyperclip
    qbittorrent-api
    textual
    transmission-rpc
  ];

  optional-dependencies = with python3.pkgs; {
    dev = [
      pytest
      ruff
    ];
  };

  pythonImportsCheck = [
    "tewi"
  ];

  meta = {
    description = "Text-based interface for BitTorrent clients (Transmission, qBittorrent, Deluge)";
    homepage = "https://github.com/anlar/tewi";
    changelog = "https://github.com/anlar/tewi/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tewi";
  };
}
