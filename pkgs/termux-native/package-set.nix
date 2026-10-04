{
  inputs,
  pkgs,
}:
let
  # Use Nixpkgs' Android/Bionic platform for compatibility. Keep Termux-ready
  # wrappers namespaced so they cannot replace Nixpkgs bootstrap tools.
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  android = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersions = [ "27.2.12479018" ];
    platformVersions = [ ];
    buildToolsVersions = [ ];
    includeEmulator = false;
  };
  ndkRoot = "${android.ndk-bundle}/libexec/android-sdk/ndk-bundle";
  toolchain = "${ndkRoot}/toolchains/llvm/prebuilt/linux-x86_64/bin";
  minimumApi = 35;
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
    fromGo =
      {
        package,
        binary,
        buildBinary ? binary,
        skipPostInstall ? false,
        licenseFile ? null,
      }:
      pkgs.callPackage ./go-binary.nix {
        inherit
          package
          binary
          buildBinary
          skipPostInstall
          licenseFile
          ;
        targetCC = "${toolchain}/aarch64-linux-android${toString minimumApi}-clang";
      };
    pythonApplication =
      {
        package,
        python ? pkgs.python3,
        entrypoint ? null,
      }:
      pkgs.callPackage ./python-application.nix {
        inherit package python entrypoint;
      };
  in
  {
    termuxAdapters = {
      inherit
        fromGo
        fromNixpkgs
        pythonApplication
        withAptPackages
        ;
    };

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

      ssh-to-age = fromGo {
        package = pkgs.ssh-to-age;
        binary = "ssh-to-age";
        licenseFile = "${pkgs.ssh-to-age.src}/LICENSE";
      };

      eget = fromGo {
        package = pkgs.eget;
        binary = "eget";
      };

      mani = fromGo {
        package = pkgs.mani;
        binary = "mani";
        skipPostInstall = true;
      };

      rbw = withAptPackages inputs.rbw.packages.${pkgs.stdenv.hostPlatform.system}.rbw-termux [
        "ca-certificates"
      ];

      emoji-fzf = pythonApplication {
        package = pkgs.emoji-fzf;
      };

      assh = withAptPackages (fromGo {
        package = pkgs.assh;
        binary = "assh";
        skipPostInstall = true;
      }) [ "ca-certificates" ];

      rancher = withAptPackages (fromGo {
        package = pkgs.rancher;
        binary = "rancher";
        buildBinary = "cli";
        skipPostInstall = true;
      }) [ "ca-certificates" ];
    };
  }
)
