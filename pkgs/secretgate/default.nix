{
  lib,
  buildPythonApplication,
  fetchPypi,
  setuptools,
  certifi,
  click,
  cryptography,
  fastapi,
  h11,
  h2,
  httpx,
  pyyaml,
  structlog,
  uvicorn,
}:

buildPythonApplication rec {
  pname = "secretgate";
  # renovate: datasource=pypi depName=secretgate
  version = "0.8.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-I9k9M7hi/Az/UQHrJuw6UiGctxvtlpOwGB5AE2FkQZM=";
  };

  build-system = [ setuptools ];

  dependencies = [
    certifi
    click
    cryptography
    fastapi
    h11
    h2
    httpx
    pyyaml
    structlog
    uvicorn
  ]
  ++ uvicorn.optional-dependencies.standard;

  pythonImportsCheck = [ "secretgate" ];

  meta = {
    description = "TLS-intercepting proxy that scans and redacts secrets in AI coding tool traffic";
    homepage = "https://github.com/secretgate/secretgate";
    license = lib.licenses.asl20;
    mainProgram = "secretgate";
  };
}
