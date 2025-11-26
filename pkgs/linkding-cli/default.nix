{
  lib,
  python3,
  fetchPypi,
  fetchFromGitHub,
  installShellFiles,
}:

let
  aiolinkding = python3.pkgs.buildPythonPackage rec {
    pname = "aiolinkding";
    version = "2025.2.0";
    pyproject = true;

    src = fetchPypi {
      pname = "aiolinkding";
      inherit version;
      hash = "sha256-WuPPwClNhIthC4R7802kFFmg0DII+GMswJ0QYodaQZc=";
    };

    postPatch = ''
      substituteInPlace pyproject.toml --replace "poetry-core==2.0.1" "poetry-core"
    '';

    build-system = [
      python3.pkgs.poetry-core
    ];

    nativeBuildInputs = [
      python3.pkgs.pythonRelaxDepsHook
    ];

    pythonRelaxDeps = [
      "frozenlist"
      "packaging"
    ];

    dependencies = with python3.pkgs; [
      aiohttp
      certifi
      frozenlist
      packaging
      yarl
    ];

    pythonImportsCheck = [
      "aiolinkding"
    ];

    meta = {
      description = "Async Python client for linkding";
      homepage = "https://github.com/bachya/aiolinkding";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [ pschmitt ];
    };
  };
in

python3.pkgs.buildPythonApplication rec {
  pname = "linkding-cli";
  version = "2024.09.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "bachya";
    repo = "linkding-cli";
    rev = version;
    hash = "sha256-qGL5Fe8N602Euw2FD1ZiOmyhkxSgxieYR4t1aXCbGJU=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml --replace "poetry-core==1.9.0" "poetry-core"
  '';

  build-system = [
    python3.pkgs.poetry-core
  ];

  nativeBuildInputs = [
    python3.pkgs.pythonRelaxDepsHook
    installShellFiles
  ];

  pythonRelaxDeps = [
    "typer"
  ];

  dependencies = with python3.pkgs; [
    aiohttp
    aiolinkding
    frozenlist
    multidict
    ruamel-yaml
    shellingham
    typer
    yarl
  ];

  pythonImportsCheck = [
    "linkding_cli"
  ];

  postInstall = ''
    installShellCompletion --cmd linkding --bash <($out/bin/linkding --show-completion bash)
    installShellCompletion --cmd linkding --zsh <($out/bin/linkding --show-completion zsh)
  '';

  meta = {
    description = "A CLI to interface with an instance of linkding";
    homepage = "https://github.com/bachya/linkding-cli";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "linkding";
  };
}
