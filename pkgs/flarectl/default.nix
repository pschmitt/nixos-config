{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "flarectl";
  version = "0.80.0";

  src = fetchFromGitHub {
    owner = "cloudflare";
    repo = "cloudflare-go";
    rev = "v${version}";
    sha256 = "sha256-Dks5tF+mHVmtj8Uh8eK50ZPZTW8p65Da08EHUnLfF7g=";
  };

  subPackages = [ "cmd/flarectl" ];
  vendorSha256 = "sha256-gQxHJNPLVcnilMIv4drDCcQ8QJCyuZ6vejsuo0elIPw=";

  # FIXME Why aren't these working?
  # Below works...
  # go build -ldflags "-s -w -X main.version=nooo" ./cmd/flarectl
  ldFlags = [
    "-s" "-w"
    "-X main.version=${version}"
    "-X main.revision=${src.rev}"
  ];

  meta = with lib; {
    description = "Go library for the Cloudflare v4 API";
    homepage = "https://github.com/cloudflare/cloudflare-go";
    license = licenses.bsd3;
    maintainers = [ maintainers.pschmitt ];
    platforms = platforms.unix;
  };
}
