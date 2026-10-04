{ pkgs }:
pkgs.callPackage ./go-binary.nix {
  licenseFile = "${pkgs.ssh-to-age.src}/LICENSE";
  package = pkgs.ssh-to-age;
  binary = "ssh-to-age";
}
