# The pinned session manifest `nixpp init` reads (share/nixpp/manifest.json).
#
# It names aarch64-linux outputs. The seed contains guest nixpp; `nixpp init`
# copies missing packages from cache.nixos.org. Only the store path
# strings are recorded: the build does not realise these packages, so the
# manifest carries no references.
{
  pkgs,
  inputs,
  guestNixpp,
}:
let
  guest = import inputs.nixpkgs { system = "aarch64-linux"; };
  path = drv: builtins.unsafeDiscardStringContext (toString drv);

  nix = guest.nixVersions.nix_2_34;
  shell = guest.bashInteractive;
  packages = [
    shell
    guest.zsh
    guest.coreutils
    guest.findutils
    guest.gnugrep
    guest.gnused
    guest.gawk
    guest.less
    guest.gitMinimal
    guest.openssh
    guest.python3
    guest.ncurses
    guest.cacert
    nix
    guestNixpp
  ];
in
pkgs.writeText "manifest.json" (
  builtins.toJSON {
    schema = 1;
    system = "aarch64-linux";
    pageSize = 4096;
    packages = map path packages;
    path = builtins.concatStringsSep ":" (map (drv: "${path drv}/bin") packages);
    shell = "${path shell}/bin/bash";
    zsh = "${path guest.zsh}/bin/zsh";
    python = "${path guest.python3}/bin/python3";
    nix = "${path nix}/bin/nix";
    certificate = "${path guest.cacert}/etc/ssl/certs/ca-bundle.crt";
    terminfo = "${path guest.ncurses}/share/terminfo";
  }
)
