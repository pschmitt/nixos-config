{
  inputs,
  pkgs,
}:
let
  target = import ./target.nix { inherit pkgs; };
  # Use Nixpkgs' Android/Bionic platform for compatibility. Keep Termux-ready
  # wrappers namespaced so they cannot replace Nixpkgs bootstrap tools.
  androidPkgs = target.pkgs;
in
androidPkgs.extend (
  _final: _prev:
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
        binaryPathOverride ? null,
        skipPostInstall ? false,
        skipPostFixup ? false,
      }:
      pkgs.callPackage ./from-nixpkgs.nix {
        inherit
          package
          crossPackage
          binaryPathOverride
          skipPostInstall
          skipPostFixup
          target
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
        targetCC = target.cc;
        inherit
          package
          binary
          buildBinary
          skipPostInstall
          licenseFile
          target
          ;
      };
    pythonApplication =
      {
        package,
        python ? pkgs.python3,
        entrypoint ? null,
        extraRuntimePackages ? [ ],
      }:
      pkgs.callPackage ./python-application.nix {
        inherit
          package
          python
          entrypoint
          extraRuntimePackages
          ;
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

      ssh-to-age = fromGo {
        package = pkgs.ssh-to-age;
        binary = "ssh-to-age";
        licenseFile = "${pkgs.ssh-to-age.src}/LICENSE";
      };

      eget = fromGo {
        package = pkgs.eget;
        binary = "eget";
        skipPostInstall = true;
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
        package = pkgs.callPackage ../emoji-fzf {
          python3 = pkgs.python312;
        };
        python = pkgs.python312;
      };

      jc = pythonApplication {
        package = pkgs.jc;
      };

      obs-cli =
        let
          obsCliPackages = inputs.obs-cli.packages.${pkgs.stdenv.hostPlatform.system};
        in
        withAptPackages (pythonApplication {
          package = obsCliPackages.obs-cli;
          python = pkgs.python312;
          extraRuntimePackages = obsCliPackages.obsws-python.propagatedBuildInputs;
        }) [ "python" ];

      slack-react = pythonApplication {
        package = inputs.slack-react.packages.${pkgs.stdenv.hostPlatform.system}.default;
        python = pkgs.python312;
      };

      jc = pythonApplication {
        package = pkgs.jc;
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
