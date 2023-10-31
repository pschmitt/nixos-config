{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "hacompanion";
  version = "1.0.8"; # You might want to replace this with the actual version.

  src = fetchFromGitHub {
    owner = "tobias-kuendig";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-rEkVxoTekVgUeLHa5iD5hutHdiLX67B96FBALE1IH9I="; # This needs to be the actual hash value for the src
  };

  vendorSha256 = "sha256-ZZ8nxN+zUeFhSXyoHLMgzeFllnIkKdoVnbVK5KjrLEQ="; # This needs to be the actual hash value for the vendor directory

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
