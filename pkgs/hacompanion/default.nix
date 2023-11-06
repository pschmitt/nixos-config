{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "hacompanion";
  version = "1.0.9";

  src = fetchFromGitHub {
    owner = "tobias-kuendig";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-UAJNvN/FN7DNWFdv45zUmn6WpSpnhnau/rMeo2LytaQ=";
  };

  vendorSha256 = "sha256-ZZ8nxN+zUeFhSXyoHLMgzeFllnIkKdoVnbVK5KjrLEQ=";

  # If the Go application has any build flags or environment variables, set them here.
  # buildFlagsArray = [ "-ldflags=-X main.Version=${version}" ];

  meta = with lib; {
    description = "Daemon that sends local hardware information to Home Assistant";
    homepage = "https://github.com/tobias-kuendig/hacompanion";
    license = licenses.mit;
    maintainers = [ maintainers.pschmitt ];
    platforms = platforms.unix;
  };
}
