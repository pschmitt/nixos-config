{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "flarectl";
  version = "6.4.0";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "cloudflare-go";
    rev = "v${version}";
    sha256 = "sha256-9hTdg3zF7j6ffvnyx2qb9ZbbQUbZg/XR2s1pkPFDL9s=";
  };

  subPackages = [ "cmd/flarectl" ];
  vendorHash = "sha256-weXaSUDNm4uyjraVpdEaFLIuMLz91iAGV5TCUyWrInY=";

  # FIXME Why aren't these working?
  # Below works...
  # go build -ldflags "-s -w -X main.version=nooo" ./cmd/flarectl
  ldFlags = [
    "-s"
    "-w"
    "-X main.version=${version}"
    "-X main.revision=${src.rev}"
  ];

  meta = with lib; {
    description = "Go library for the Cloudflare v4 API";
    homepage = "https://github.com/cloudflare/cloudflare-go";
    license = licenses.bsd3;
    maintainers = [ maintainers.pschmitt ];
    platforms = platforms.unix;
    mainProgram = "flarectl";
  };
}
