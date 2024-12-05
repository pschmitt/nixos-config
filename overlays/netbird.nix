{ final, prev }:
{
  netbird = prev.netbird.overrideAttrs (
    oldAttrs:
    let
      version = "0.34.1";
    in
    {
      pname = "netbird";
      version = version;

      src = prev.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        rev = "v${version}";
        hash = "sha256-UQ91Xjw7RTtTMCrCKyv8tk08hhgyXbjG+QKuVjNk4kM=";
      };

      vendorHash = "sha256-8ML6s+XPhciYHhWfUOQqgN2XSSqgZ9ULZ6+arWgQjMY=";

      ldflags = [
        "-s"
        "-w"
        "-X github.com/netbirdio/netbird/version.version=${version}"
        "-X main.builtBy=nix"
      ];

    }
  );
}
