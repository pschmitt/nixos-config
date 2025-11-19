{
  lib,
  buildPythonApplication,
  fetchFromGitHub,
  hatchling,
  pkgs,
}:

buildPythonApplication {
  pname = "withoutbg";
  version = "0.0.0-unstable-2025-11-17";

  src = fetchFromGitHub {
    owner = "withoutbg";
    repo = "withoutbg";
    rev = "8885808fbcd9dbe9e8b1c14f044902e819dc3724";
    hash = "sha256-hTrdL8hIFTkB1EHrIULZVE8MTo0SXoBGhaGwRU7VGS4=";
  };

  pyproject = true;

  nativeBuildInputs = [
    hatchling
  ];

  propagatedBuildInputs = with pkgs.python3Packages; [
    click
    huggingface-hub
    numpy
    onnxruntime
    pillow
    requests
    tqdm
  ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace 'onnxruntime>=1.12.0,<1.20.0' 'onnxruntime>=1.12.0'
  '';

  sourceRoot = "source/packages/python";

  meta = with lib; {
    description = "AI-powered background removal with local and cloud options";
    homepage = "https://withoutbg.com";
    license = licenses.asl20;
    maintainers = with maintainers; [ pschmitt ];
  };
}
