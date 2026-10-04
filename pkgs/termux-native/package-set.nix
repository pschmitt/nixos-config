{
  inputs,
  pkgs,
}:
let
  # Use Nixpkgs' Android/Bionic platform for compatibility. Keep Termux-ready
  # wrappers namespaced so they cannot replace Nixpkgs bootstrap tools.
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
in
androidPkgs.extend (
  _final: prev:
  let
    withAptPackages =
      package: aptPackages:
      package.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          termuxNative = (old.passthru.termuxNative or { }) // {
            inherit aptPackages;
          };
        };
      });
    fromNixpkgs =
      {
        package,
        crossPackage ? null,
        skipPostInstall ? false,
        skipPostFixup ? false,
      }:
      pkgs.callPackage ./from-nixpkgs.nix {
        inherit
          package
          crossPackage
          skipPostInstall
          skipPostFixup
          ;
      };
    goBinary =
      {
        package,
        binary,
        buildBinary ? binary,
        skipPostInstall ? false,
      }:
      pkgs.callPackage ./go-binary.nix {
        inherit
          package
          binary
          buildBinary
          skipPostInstall
          ;
      };
  in
  {
    termuxPackages = {
      nixpp = withAptPackages (pkgs.callPackage ../nixpp-termux { inherit inputs; }) [
        "ca-certificates"
      ];

      bat = withAptPackages (fromNixpkgs {
        package = pkgs.bat;
        # Nix wraps bat with a store-specific less path; Termux supplies less on PATH.
        skipPostFixup = true;
      }) [ "less" ];

      eza = fromNixpkgs {
        package = pkgs.eza;
        # The export contract ships eza's executable, not its Pandoc-built docs.
        skipPostInstall = true;
        crossPackage = prev.eza.overrideAttrs (old: {
          outputs = [ "out" ];
          meta = (old.meta or { }) // {
            outputsToInstall = [ "out" ];
          };
          nativeBuildInputs = builtins.filter (input: pkgs.lib.getName input != "pandoc-cli") (
            old.nativeBuildInputs or [ ]
          );
        });
      };

      fd = fromNixpkgs { package = pkgs.fd; };

      zip = pkgs.callPackage ./zip.nix { package = prev.zip; };

      unzip = pkgs.callPackage ./unzip.nix {
        inherit (prev) bzip2;
        package = prev.unzip;
      };

      ripgrep = fromNixpkgs {
        package = pkgs.ripgrep;
        # The upstream hook runs the Android binary under QEMU to generate docs;
        # QEMU has no Android system linker on the build host.
        skipPostFixup = true;
        crossPackage = prev.ripgrep.override { withPCRE2 = true; };
      };

      gzip = pkgs.callPackage ./gzip.nix { package = prev.gzip; };

      ssh-to-age = pkgs.callPackage ./ssh-to-age.nix { inherit pkgs; };

      rbw = withAptPackages inputs.rbw.packages.${pkgs.stdenv.hostPlatform.system}.rbw-termux [
        "ca-certificates"
      ];

      emoji-fzf = pkgs.callPackage ./python-application.nix {
        package = pkgs.emoji-fzf;
        python = pkgs.python3;
      };

      assh = withAptPackages (goBinary {
        package = pkgs.assh;
        binary = "assh";
        skipPostInstall = true;
      }) [ "ca-certificates" ];

      rancher = withAptPackages (goBinary {
        package = pkgs.rancher;
        binary = "rancher";
        buildBinary = "cli";
        skipPostInstall = true;
      }) [ "ca-certificates" ];
    };
  }
)
