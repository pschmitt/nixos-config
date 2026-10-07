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
    inherit (pkgs) lib;
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
        binaryPaths ? null,
        extraFiles ? [ ],
        scripts ? [ ],
        trees ? [ ],
        aptPackages ? [ ],
        aptLibraries ? [ ],
        runtimeInputs ? [ ],
        runtimeLibraries ? [ ],
        skipPostInstall ? false,
        skipPostFixup ? false,
      }:
      pkgs.callPackage ./from-nixpkgs.nix {
        inherit
          package
          crossPackage
          binaryPathOverride
          binaryPaths
          extraFiles
          scripts
          trees
          aptPackages
          aptLibraries
          runtimeInputs
          runtimeLibraries
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
        skipPostFixup ? false,
        licenseFile ? null,
      }:
      pkgs.callPackage ./go-binary.nix {
        inherit
          package
          binary
          buildBinary
          skipPostInstall
          skipPostFixup
          licenseFile
          target
          ;
      };
    termuxShellScripts =
      {
        package,
        scripts,
        aptPackages ? [ ],
      }:
      let
        scriptPaths = map (script: "bin/${script.command}") scripts;
        packageMeta = package.meta or { };
        installScripts = lib.concatMapStringsSep "\n" (script: ''
          {
            printf '%s\n' '#!${target.prefix}/bin/bash'
            ${pkgs.coreutils}/bin/tail -n +2 \
              ${lib.escapeShellArg "${package.src}/${script.source}"}
          } > "$out/bin/${script.command}"
          chmod 0755 "$out/bin/${script.command}"
        '') scripts;
      in
      assert scripts != [ ];
      assert lib.all (script: builtins.match "[A-Za-z0-9._+-]+" script.command != null) scripts;
      pkgs.runCommand "${lib.getName package}-termux"
        {
          allowedReferences = [ ];
          passthru.termuxNative = {
            abi = "android-bionic";
            files = scriptPaths;
            binaries = [ ];
            scripts = scriptPaths;
            trees = [ ];
            inherit aptPackages;
          };
          meta = packageMeta // {
            mainProgram = packageMeta.mainProgram or (builtins.head (map (script: script.command) scripts));
          };
        }
        ''
          mkdir -p "$out/bin"
          ${installScripts}
        '';
    pythonApplication =
      {
        package,
        python ? pkgs.python3,
        entrypoint ? null,
        checkEntrypoint ? true,
        extraRuntimePackages ? [ ],
        excludedRuntimePackages ? [ ],
        extraFiles ? [ ],
      }:
      pkgs.callPackage ./python-application.nix {
        inherit
          package
          python
          entrypoint
          checkEntrypoint
          extraRuntimePackages
          excludedRuntimePackages
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
        charset-normalizer =
          (previous.charset-normalizer.override {
            withMypyc = false;
          }).overridePythonAttrs
            (_: {
              doCheck = false;
              nativeCheckInputs = [ ];
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
    mylDiscovery = python312Termux.pkgs.buildPythonApplication {
      pname = "myl-discovery";
      version = builtins.readFile "${inputs.myl-discovery}/myl-discovery-version.txt";
      pyproject = true;
      src = inputs.myl-discovery;
      pythonRelaxDeps = [ "rich" ];
      nativeBuildInputs = with python312Termux.pkgs; [
        setuptools
        setuptools-scm
      ];
      dependencies = with python312Termux.pkgs; [
        dnspython
        exchangelib
        requests
        rich
        xmltodict
      ];
      pythonImportsCheck = [ "myldiscovery" ];
    };
    myl = python312Termux.pkgs.buildPythonApplication {
      pname = "myl";
      version = builtins.readFile "${inputs.myl}/myl-version.txt";
      pyproject = true;
      src = inputs.myl;
      pythonRelaxDeps = [ "rich" ];
      nativeBuildInputs = with python312Termux.pkgs; [
        setuptools
        setuptools-scm
      ];
      dependencies = with python312Termux.pkgs; [
        html2text
        imap-tools
        mylDiscovery
        rich
      ];
      pythonImportsCheck = [ "myl" ];
    };
  in
  {
    termuxAdapters = {
      inherit
        fromGo
        fromNixpkgs
        pythonApplication
        termuxShellScripts
        withAptPackages
        ;
    };

    termuxPackages = {
      adb-sh = pkgs.callPackage ./adb-sh.nix { inherit pkgs; };

      nixpp = withAptPackages (pkgs.callPackage ../nixpp-termux { inherit inputs; }) [
        "ca-certificates"
      ];

      hwatch = fromNixpkgs {
        package = pkgs.hwatch;
      };

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

      krew = withAptPackages (fromGo {
        package = pkgs.krew;
        binary = "krew";
        # Nixpkgs wraps krew with its Git path; Termux APT owns Git instead.
        skipPostFixup = true;
      }) [ "git" ];

      ketall = withAptPackages (fromGo {
        package = pkgs.ketall;
        binary = "ketall";
        licenseFile = "${pkgs.ketall.src}/LICENSE";
      }) [ "ca-certificates" ];

      kubectlKsh = termuxShellScripts {
        package = pkgs.kubectl-ksh;
        scripts = [
          {
            command = "kubectl-delete_all";
            source = "kubectl-delete-all.sh";
          }
          {
            command = "kubectl-list_all";
            source = "kubectl-list-all.sh";
          }
          {
            command = "kubectl-reveal_secret";
            source = "kubectl-reveal-secret.sh";
          }
        ];
        aptPackages = [
          "bash"
          "coreutils"
          "findutils"
          "gawk"
          "grep"
          "jq"
          "kubectl"
          "sed"
          "util-linux"
        ];
      };

      kubectlSocks5Proxy = termuxShellScripts {
        package = pkgs.kubectl-socks5-proxy;
        scripts = [
          {
            command = "kubectl-socks5_proxy";
            source = "kubectl-socks5-proxy";
          }
        ];
        aptPackages = [
          "bash"
          "coreutils"
          "gawk"
          "grep"
          "kubectl"
          "ncurses-utils"
          "sed"
          "util-linux"
        ];
      };

      kubectlWatch = termuxShellScripts {
        package = pkgs.kubectl-watch;
        scripts = [
          {
            command = "kubectl-watch";
            source = "kubectl-watch";
          }
        ];
        aptPackages = [
          "bash"
          "coreutils"
          "gawk"
          "grep"
          "jq"
          "kubecolor"
          "kubectl"
          "ncurses-utils"
          "sed"
        ];
      };

      netbirdCli = termuxShellScripts {
        package = pkgs.netbird-cli;
        scripts = [
          {
            command = "netbird-cli";
            source = "netbird-cli.sh";
          }
        ];
        aptPackages = [
          "bash"
          "coreutils"
          "curl"
          "gawk"
          "grep"
          "jq"
          "sed"
          "util-linux"
        ];
      };

      tmux-slay = pkgs.callPackage ./tmux-slay.nix { inherit inputs; };

      tmux-xpanes = pkgs.callPackage ./tmux-xpanes.nix { inherit inputs; };

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

      myl =
        withAptPackages
          (pythonApplication {
            package = myl;
            python = python312Termux;
            checkEntrypoint = false;
            excludedRuntimePackages = with python312Termux.pkgs; [
              cffi
              cryptography
              lxml
            ];
          })
          [
            "python-cryptography"
            "python-lxml"
          ];

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
