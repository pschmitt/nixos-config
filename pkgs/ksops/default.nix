{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "ksops";
  version = "4.4.0";

  src = fetchFromGitHub {
    owner = "viaduct-ai";
    repo = "kustomize-sops";
    rev = "v${version}";
    hash = "sha256-a9SvkHt8ZQFobOjKAECSJcRZEeRE8pTKLnXN4DYNa7k=";
  };

  vendorHash = "sha256-ajXW6H1XBgVtMdK7/asfpy6e3rFAD2pz3Lg+QFnkVpo=";

  doCheck = false;

  postInstall = ''
    mv "$out/bin/kustomize-sops" "$out/bin/ksops"
  '';

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "KSOPS - A Flexible Kustomize Plugin for SOPS Encrypted Resources";
    homepage = "https://github.com/viaduct-ai/kustomize-sops";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "ksops";
  };
}
