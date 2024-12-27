{ final, prev }:
{
  netbird = prev.netbird.overrideAttrs (
    oldAttrs:
    let
      version = "0.35.1";
    in
    {
      pname = "netbird";
      version = version;

      src = prev.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        rev = "v${version}";
        hash = "sha256-PgJm0+HqJMdDjbX+9a86BmicArJCiegf4n7A1sHNQ0Y=";
      };

      vendorHash = "sha256-CgfZZOiFDLf6vCbzovpwzt7FlO9BnzNSdR8e5U+xCDQ=";

      ldflags = [
        "-s"
        "-w"
        "-X github.com/netbirdio/netbird/version.version=${version}"
        "-X main.builtBy=nix"
      ];

    }
  );
}
