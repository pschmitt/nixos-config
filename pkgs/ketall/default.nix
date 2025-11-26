{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "ketall";
  version = "1.3.8";

  src = fetchFromGitHub {
    owner = "corneliusweig";
    repo = "ketall";
    rev = "v${version}";
    hash = "sha256-Mau57mXS78fHyeU0OOz3Tms0WNu7HixfAZZL3dmcj3w=";
  };

  vendorHash = "sha256-lxfWJ7t/IVhIfvDUIESakkL8idh+Q/wl8B1+vTpb5a4=";

  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    ln -s "$out/bin/ketall" "$out/bin/kubectl-get-all"
  '';

  meta = {
    description = "Like `kubectl get all`, but get really all resources";
    homepage = "https://github.com/corneliusweig/ketall";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "ketall";
  };
}
