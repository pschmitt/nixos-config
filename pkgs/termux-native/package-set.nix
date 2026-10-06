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
        extraFiles ? [ ],
      }:
      pkgs.callPackage ./python-application.nix {
        inherit
          package
          python
          entrypoint
          extraRuntimePackages
          extraFiles
          ;
      };
    python312Termux = pkgs.python312.override {
      packageOverrides = _python: previous: {
        aiohttp = previous.aiohttp.overridePythonAttrs (old: {
          AIOHTTP_NO_EXTENSIONS = "1";
          # These are Nixpkgs' optional speedups, not required by Linkding CLI.
          dependencies = pkgs.lib.filter (
            package:
            !(builtins.elem (package.pname or null) [
              "aiodns"
              "backports-zstd"
              "brotli"
            ])
          ) old.dependencies;
          disabledTests = (old.disabledTests or [ ]) ++ [
            "test_feed_eof_no_err_brotli"
            "test_empty_body"
          ];
        });
        frozenlist = previous.frozenlist.overridePythonAttrs (_: {
          FROZENLIST_NO_EXTENSIONS = "1";
        });
        multidict = previous.multidict.overridePythonAttrs (_: {
          MULTIDICT_NO_EXTENSIONS = "1";
          doCheck = false;
        });
        propcache = previous.propcache.overridePythonAttrs (_: {
          PROPCACHE_NO_EXTENSIONS = "1";
          disabledTests = [ "c-extension-module" ];
        });
        ruamel-yaml = previous.ruamel-yaml.overridePythonAttrs (old: {
          propagatedBuildInputs = pkgs.lib.filter (package: package != previous.ruamel-yaml-clib) (
            old.propagatedBuildInputs or [ ]
          );
        });
        shellingham = previous.shellingham.overridePythonAttrs (_: {
          # Nixpkgs normally pins `ps` to its store path; Termux supplies it via APT.
          postPatch = "";
        });
        yarl = previous.yarl.overridePythonAttrs (_: {
          YARL_NO_EXTENSIONS = "1";
        });
      };
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
        package = python312Termux.pkgs.jc;
        python = python312Termux;
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

      linkding-cli = pythonApplication {
        package = pkgs.callPackage ../linkding-cli {
          python3 = python312Termux;
        };
        python = python312Termux;
        extraFiles = [ "share/zsh/site-functions/_linkding" ];
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
