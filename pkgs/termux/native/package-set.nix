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
    pythonScriptApplication =
      {
        pname,
        src,
        sourceFile,
        python ? pkgs.python3,
        dependencies,
        entrypoint,
      }:
      let
        package = python.pkgs.buildPythonApplication {
          inherit pname src;
          version = "1.0.0";
          format = "other";
          propagatedBuildInputs = dependencies;
          dontBuild = true;
          installPhase = ''
            install -Dm644 "$src/${sourceFile}" "$out/${python.sitePackages}/${pname}.py"
          '';
        };
      in
      pythonApplication {
        inherit package python entrypoint;
        checkEntrypoint = false;
      };
    pythonTermuxOverrides = _python: previous: {
      aiohttp = previous.aiohttp.overridePythonAttrs (old: {
        env = (old.env or { }) // {
          AIOHTTP_NO_EXTENSIONS = "1";
        };
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
      django = previous.django.overridePythonAttrs (_: {
        # Django is a transitive runtime dependency of Termux CLI tools; its
        # full test suite is unrelated to exporting the application runtime.
        doCheck = false;
      });
      charset-normalizer =
        (previous.charset-normalizer.override {
          withMypyc = false;
        }).overridePythonAttrs
          (_: {
            doCheck = false;
            nativeCheckInputs = [ ];
          });
      frozenlist = previous.frozenlist.overridePythonAttrs (old: {
        env = (old.env or { }) // {
          FROZENLIST_NO_EXTENSIONS = "1";
        };
      });
      # The overrides above rebuild moto (via slack-sdk's checks) from source;
      # this test fails there with ExecutionAlreadyExists.
      moto = previous.moto.overridePythonAttrs (old: {
        # Moto is only bundled as a runtime dependency; its full service
        # emulator suite does not validate the exported Termux applications.
        doCheck = false;
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_create_state_machine_twice_after_success"
        ];
      });
      slack-sdk = previous.slack-sdk.overridePythonAttrs (_: {
        # It is shipped only as slack-react's runtime dependency; its full
        # upstream API test suite is not part of this Termux export.
        doCheck = false;
      });
      multidict = previous.multidict.overridePythonAttrs (old: {
        env = (old.env or { }) // {
          MULTIDICT_NO_EXTENSIONS = "1";
        };
        doCheck = false;
      });
      propcache = previous.propcache.overridePythonAttrs (old: {
        env = (old.env or { }) // {
          PROPCACHE_NO_EXTENSIONS = "1";
        };
        disabledTests = [ "c-extension-module" ];
      });
      ruamel-yaml = previous.ruamel-yaml.overridePythonAttrs (old: {
        propagatedBuildInputs = pkgs.lib.filter (package: package != previous.ruamel-yaml-clib) (
          old.propagatedBuildInputs or [ ]
        );
      });
      pyyaml = previous.pyyaml.overridePythonAttrs (_: {
        # Build PyYAML's pure-Python fallback; its optional libyaml extension
        # is a host ELF and cannot be included in a Termux bundle.
        buildInputs = [ ];
      });
      shellingham = previous.shellingham.overridePythonAttrs (_: {
        # Nixpkgs normally pins `ps` to its store path; Termux supplies it via APT.
        postPatch = "";
      });
      yarl = previous.yarl.overridePythonAttrs (old: {
        env = (old.env or { }) // {
          YARL_NO_EXTENSIONS = "1";
        };
      });
    };
    pythonTermux = pkgs.python3.override {
      packageOverrides = pythonTermuxOverrides;
    };
    obswsPython = pythonTermux.pkgs.buildPythonPackage rec {
      pname = "obsws-python";
      version = "1.6.2";
      pyproject = true;
      src = pythonTermux.pkgs.fetchPypi {
        pname = "obsws_python";
        inherit version;
        hash = "sha256-cR1gnZ5FxZ76SD9GlHSIhv142ejsqs/Bp8wV1A1kfdw=";
      };
      nativeBuildInputs = [ pythonTermux.pkgs.hatchling ];
      dependencies = with pythonTermux.pkgs; [
        tomli
        websocket-client
      ];
      doCheck = false;
    };
    obsCli = pythonTermux.pkgs.buildPythonApplication {
      pname = "obs-cli";
      version = "0.9.5";
      src = inputs.obs-cli;
      pyproject = true;
      nativeBuildInputs = with pythonTermux.pkgs; [
        setuptools
        setuptools-scm
        wheel
      ];
      dependencies = with pythonTermux.pkgs; [
        obswsPython
        rich
        rich-argparse
      ];
      pythonImportsCheck = [ "obs_cli" ];
    };
    slackReact = pythonTermux.pkgs.buildPythonApplication {
      pname = "slack-react";
      version = "0.3.3";
      src = inputs.slack-react;
      pyproject = true;
      nativeBuildInputs = with pythonTermux.pkgs; [
        setuptools
        setuptools-scm
      ];
      dependencies = with pythonTermux.pkgs; [
        appdirs
        certifi
        rich
        slack-sdk
      ];
      pythonImportsCheck = [ "slack_react" ];
    };
    mylDiscovery = pythonTermux.pkgs.buildPythonApplication {
      pname = "myl-discovery";
      version = builtins.readFile "${inputs.myl-discovery}/myl-discovery-version.txt";
      pyproject = true;
      src = inputs.myl-discovery;
      pythonRelaxDeps = [ "rich" ];
      nativeBuildInputs = with pythonTermux.pkgs; [
        setuptools
        setuptools-scm
      ];
      dependencies = with pythonTermux.pkgs; [
        dnspython
        exchangelib
        requests
        rich
        xmltodict
      ];
      pythonImportsCheck = [ "myldiscovery" ];
    };
    myl = pythonTermux.pkgs.buildPythonApplication {
      pname = "myl";
      version = builtins.readFile "${inputs.myl}/myl-version.txt";
      pyproject = true;
      src = inputs.myl;
      pythonRelaxDeps = [ "rich" ];
      nativeBuildInputs = with pythonTermux.pkgs; [
        setuptools
        setuptools-scm
      ];
      dependencies = with pythonTermux.pkgs; [
        html2text
        imap-tools
        mylDiscovery
        rich
      ];
      pythonImportsCheck = [ "myl" ];
    };
    homeAssistantPython = pkgs.python3.override {
      packageOverrides =
        python: previous:
        let
          termuxPackages = pythonTermuxOverrides python previous;
        in
        termuxPackages
        // {
          markupsafe = previous.markupsafe.overridePythonAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              find "$out" -type f -name '*_speedups*.so' -delete
            '';
          });
          zeroconf = previous.zeroconf.overridePythonAttrs (_: {
            SKIP_CYTHON = "1";
          });
        };
    };
    homeAssistantCli = homeAssistantPython.pkgs.buildPythonApplication {
      pname = "homeassistant-cli";
      version = pkgs.home-assistant-cli.version;
      src = pkgs.home-assistant-cli.src;
      pyproject = true;
      pythonRelaxDeps = true;
      pythonRemoveDeps = [
        "dateparser"
        "netdisco"
        "regex"
      ];
      nativeBuildInputs = [ homeAssistantPython.pkgs.poetry-core ];
      dependencies = with homeAssistantPython.pkgs; [
        aiohttp
        click
        click-log
        jinja2
        jsonpath-ng
        requests
        ruamel-yaml
        tabulate
        zeroconf
      ];
      pythonImportsCheck = [ "homeassistant_cli" ];
      meta.mainProgram = "hass-cli";
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

      nixpp = withAptPackages (pkgs.callPackage ../nixpp { inherit inputs; }) [
        "ca-certificates"
      ];

      hwatch = fromNixpkgs {
        package = pkgs.hwatch;
      };

      xcp = termuxShellScripts {
        package = {
          pname = "xcp";
          src = pkgs.runCommand "xcp-termux-source" { } ''
            mkdir -p "$out"
            {
              printf '%s\n' '#!/bin/bash'
              cat ${../../local/xcp/xcp.sh}
            } > "$out/xcp.sh"
          '';
          meta = pkgs.xcp.meta;
        };
        scripts = [
          {
            command = "xcp";
            source = "xcp.sh";
          }
        ];
        aptPackages = [ "termux-api" ];
      };

      nbx = termuxShellScripts {
        package = {
          pname = "nbx";
          src = inputs.nbx;
          meta.mainProgram = "nbx";
        };
        scripts = [
          {
            command = "nbx";
            source = "nbx.sh";
          }
        ];
        aptPackages = [
          "bash"
          "coreutils"
          "curl"
          "fzf"
          "gawk"
          "grep"
          "jq"
          "util-linux"
        ];
      };

      yank = termuxShellScripts {
        package = {
          pname = "yank";
          src = pkgs.yank-osc52.src;
          meta.mainProgram = "yank";
        };
        scripts = [
          {
            command = "yank";
            source = "bin/yank";
          }
        ];
        aptPackages = [
          "coreutils"
          "grep"
          "tmux"
        ];
      };

      zhj =
        pkgs.runCommand "zhj-termux"
          {
            allowedReferences = [ ];
            passthru.termuxNative = {
              abi = "android-bionic";
              files = [ "bin/zhj" ];
              binaries = [ ];
              scripts = [ "bin/zhj" ];
              trees = [ ];
              aptPackages = [
                "bash"
                "zsh"
              ];
            };
            meta = {
              description = "Run commands with the Termux native Zsh configuration loaded";
              mainProgram = "zhj";
              platforms = lib.platforms.unix;
            };
          }
          ''
            mkdir -p "$out/bin"
            cat > "$out/bin/zhj" <<'EOF'
            #!${target.prefix}/bin/bash
            set -e
            PREFIX="''${PREFIX:-/data/data/com.termux/files/usr}"
            TERMUX_GENERATION="''${TERMUX_GENERATION:-$HOME/.local/share/termux-native/current}"
            TERMUX_GENERATION="$(cd "$TERMUX_GENERATION" && pwd -P)"
            export PREFIX TERMUX_GENERATION
            export ZDOTDIR="$TERMUX_GENERATION/home/.config/zsh"
            exec "$PREFIX/bin/zsh" -f -c 'source "$ZDOTDIR/zhj.zsh" "$@"' zhj "$@"
            EOF
            chmod 0755 "$out/bin/zhj"
          '';

      ssh-to-age = fromGo {
        package = pkgs.ssh-to-age;
        binary = "ssh-to-age";
        licenseFile = "${pkgs.ssh-to-age.src}/LICENSE";
      };

      sops = fromGo {
        package = pkgs.sops;
        binary = "sops";
        licenseFile = "${pkgs.sops.src}/LICENSE";
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
        package = pkgs.callPackage ../../emoji-fzf {
          inherit (pkgs) python3;
        };
        python = pkgs.python3;
      };

      jc = pythonApplication {
        package = pythonTermux.pkgs.jc;
        python = pythonTermux;
      };

      pycolumn = pythonScriptApplication {
        pname = "pycolumn";
        src = ../../local/pycolumn;
        sourceFile = "pycolumn.py";
        dependencies = [ pythonTermux.pkgs.wcwidth ];
        entrypoint = "pycolumn:main";
      };

      tsvtool =
        let
          package = pythonTermux.pkgs.buildPythonApplication {
            pname = "tsvtool";
            version = "0.1.0";
            src = inputs.tsvtool;
            format = "other";
            patches = [ ./patches/tsvtool-pure-python.patch ];
            propagatedBuildInputs = with pythonTermux.pkgs; [
              rich
              rich-argparse
              pyyaml
              tomli
              tomli-w
              wcwidth
            ];
            dontBuild = true;
            installPhase = ''
              install -Dm644 tsvtool "$out/${pythonTermux.sitePackages}/tsvtool.py"
            '';
          };
        in
        pythonApplication {
          inherit package;
          python = pythonTermux;
          entrypoint = "tsvtool:main";
        };

      ldifj =
        let
          ldifjPackage = pythonTermux.pkgs.buildPythonApplication {
            pname = "ldifj";
            version = "0.1.1";
            src = inputs.ldifj;
            pyproject = true;
            nativeBuildInputs = with pythonTermux.pkgs; [
              setuptools
              setuptools-scm
            ];
            pythonRemoveDeps = [ "python-ldap" ];
            dependencies = with pythonTermux.pkgs; [
              rich
              rich-argparse
            ];
            doCheck = false;
          };
          ldifModule = pkgs.runCommand "python-ldif-module" { } ''
            module_source=${pythonTermux.pkgs.python-ldap.src}
            install -Dm644 \
              "$module_source/Lib/ldif.py" \
              "$out/${pythonTermux.sitePackages}/ldif.py"
            install -Dm644 "$module_source/LICENCE" \
              "$out/${pythonTermux.sitePackages}/python-ldap-LICENCE.txt"
          '';
        in
        pythonApplication {
          package = ldifjPackage;
          python = pythonTermux;
          entrypoint = "ldifj:main";
          extraRuntimePackages = [ ldifModule ];
        };

      zebra = pythonScriptApplication {
        pname = "zebra";
        src = ../../local/zebra;
        sourceFile = "zebra.py";
        dependencies = [ pkgs.python3Packages.wcwidth ];
        entrypoint = "zebra:main";
      };

      obs-cli = withAptPackages (pythonApplication {
        package = obsCli;
        python = pythonTermux;
        extraRuntimePackages = obswsPython.propagatedBuildInputs;
      }) [ "python" ];

      home-assistant-cli = withAptPackages (pythonApplication {
        package = homeAssistantCli;
        python = pythonTermux;
      }) [ "python" ];

      slack-react = pythonApplication {
        package = slackReact;
        python = pythonTermux;
      };

      linkding-cli = pythonApplication {
        package = pkgs.callPackage ../../linkding-cli {
          python3 = pythonTermux;
        };
        python = pythonTermux;
        extraFiles = [ "share/zsh/site-functions/_linkding" ];
      };

      myl =
        withAptPackages
          (pythonApplication {
            package = myl;
            python = pythonTermux;
            checkEntrypoint = false;
            excludedRuntimePackages = with pythonTermux.pkgs; [
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
