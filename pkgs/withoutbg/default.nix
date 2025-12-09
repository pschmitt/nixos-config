{
  lib,
  buildPythonApplication,
  fetchFromGitHub,
  hatchling,
  pkgs,
  nix-update-script,
}:

let
  isnet-model = pkgs.fetchurl {
    url = "https://huggingface.co/withoutbg/focus/resolve/main/isnet.onnx";
    sha256 = "0kpnc7nraf8whbiik4s6y3r9h1386h433rnffilmh7xasc25ycy3";
  };
  depth-anything-model = pkgs.fetchurl {
    url = "https://huggingface.co/withoutbg/focus/resolve/main/depth_anything_v2_vits_slim.onnx";
    sha256 = "1xq9qrxvchkgwzy8smzn07r7rp1cnz5j9njssjgza40m60sc4srr";
  };
  focus-matting-model = pkgs.fetchurl {
    url = "https://huggingface.co/withoutbg/focus/resolve/main/focus_matting_1.0.0.onnx";
    sha256 = "1rvy1z3krxk06dsk7hqvwj3c6s2yrpkgyp9p8q8hyrwx1j7d9i1a";
  };
  focus-refiner-model = pkgs.fetchurl {
    url = "https://huggingface.co/withoutbg/focus/resolve/main/focus_refiner_1.0.0.onnx";
    sha256 = "0yw4lzrjl2373xag1043k254hi0qh600yf6nq7mdbjir2pcqjnfa";
  };
in
buildPythonApplication {
  pname = "withoutbg";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "withoutbg";
    repo = "withoutbg";
    rev = "8885808fbcd9dbe9e8b1c14f044902e819dc3724";
    hash = "sha256-hTrdL8hIFTkB1EHrIULZVE8MTo0SXoBGhaGwRU7VGS4=";
  };

  pyproject = true;

  nativeBuildInputs = [
    hatchling
    pkgs.makeWrapper
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

  postInstall = ''
    wrapProgram $out/bin/withoutbg \
      --set WITHOUTBG_ISNET_MODEL_PATH "${isnet-model}" \
      --set WITHOUTBG_DEPTH_MODEL_PATH "${depth-anything-model}" \
      --set WITHOUTBG_MATTING_MODEL_PATH "${focus-matting-model}" \
      --set WITHOUTBG_REFINER_MODEL_PATH "${focus-refiner-model}"
  '';

  sourceRoot = "source/packages/python";

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--flake" ];
  };

  meta = with lib; {
    description = "AI-powered background removal with local and cloud options";
    homepage = "https://withoutbg.com";
    license = licenses.asl20;
    maintainers = with maintainers; [ pschmitt ];
  };
}
