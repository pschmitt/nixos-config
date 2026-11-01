{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    # Old nixpkgs revisions pinned for legacy tool versions (overlays.old-packages).
    # https://lazamar.co.uk/nix-versions/?channel=nixpkgs-unstable&package=kubectl
    nixpkgs-kubectl-123 = {
      url = "github:NixOS/nixpkgs/611bf8f183e6360c2a215fa70dfd659943a9857f";
      flake = false;
    };
    nixpkgs-terraform-157 = {
      url = "github:NixOS/nixpkgs/4ab8a3de296914f3b631121e9ce3884f1d34e1e5";
      flake = false;
    };

    # Main user's public SSH keys (mainUser.authorizedKeys); `nix flake update
    # github-keys` picks up key changes.
    github-keys = {
      url = "file+https://github.com/pschmitt.keys";
      flake = false;
    };

    # Shared flake plumbing; other inputs follow these to keep flake.lock lean.
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    systems.url = "github:nix-systems/default";

    zsh-diff-so-fancy = {
      url = "github:z-shell/zsh-diff-so-fancy";
      flake = false;
    };

    anika-blue = {
      url = "github:pschmitt/anika-blue";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    bunq-sh = {
      url = "github:pschmitt/bunq-sh";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    codex-ha-bridge = {
      url = "github:pschmitt/codex-ha-bridge";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bruvtab = {
      url = "github:pschmitt/bruvtab";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    browser-daemon = {
      url = "github:pschmitt/browser-daemon";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        # The live view's vault comes from rbw: the same release as ours.
        rbw.follows = "rbw";
      };
    };

    declaroid = {
      url = "github:pschmitt/declaroid";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tsvtool = {
      url = "github:pschmitt/tsvtool";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stricknani = {
      url = "github:pschmitt/stricknani";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        pre-commit-hooks.follows = "pre-commit-hooks";
      };
    };

    # Isolated Rust candidate; the production stricknani input stays pinned separately.
    stricknani-rust = {
      url = "github:pschmitt/stricknani/7162771a3150ea2f64a45b5980c115905ec84982";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        pre-commit-hooks.follows = "pre-commit-hooks";
      };
    };

    monarch = {
      url = "github:pschmitt/monarch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    teams-auth-source = {
      url = "github:pschmitt/homeassistant-msteams";
      flake = false;
    };

    teams-live = {
      url = "github:pschmitt/teams-live";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        browser-daemon.follows = "browser-daemon";
        teams-auth-source.follows = "teams-auth-source";
      };
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-images = {
      url = "github:nix-community/nixos-images";
      # Deliberately not following our nixpkgs: it pins its own
      # nixos-unstable/nixos-stable and composes its kexec-installer module
      # against that specific pin.
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/v5.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-plugins = {
      url = "github:pschmitt/noctalia-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.noctalia.follows = "noctalia";
    };

    rbw-auto = {
      # url = "path:/home/pschmitt/devel/private/pschmitt/rbw-auto.git";
      url = "github:pschmitt/rbw-auto";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rbw.follows = "rbw";
      };
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs = {
        flake-parts.follows = "flake-parts";
        systems.follows = "systems";
      };
    };

    fenix = {
      url = "github:nix-community/fenix/monthly";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    falcon-sensor = {
      url = "github:benley/falcon-sensor-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks = {
      # https://github.com/GermanBread/declarative-flatpak/blob/dev/docs/branches.md
      url = "github:in-a-dil-emma/declarative-flatpak/v3.1.0";
      # NOTE Do *not* override nixpkgs, it is not supported
    };

    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        systems.follows = "systems";
      };
    };

    hardware.url = "github:nixos/nixos-hardware";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      # url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Only its NixOS module is used (services/ai-memory.nix); the package
    # comes from llm-agents.
    ai-memory = {
      url = "github:akitaonrails/ai-memory";
      flake = false;
    };

    manydots = {
      url = "github:knu/zsh-manydots-magic/4372de0718714046f0c7ef87b43fc0a598896af6";
      flake = false;
    };

    zsh-completions = {
      url = "github:zsh-users/zsh-completions";
      flake = false;
    };

    # jq modules (~/.config/jq/{colors,plib}, `jq -L ~/.config/jq`)
    colors-jq = {
      url = "github:pschmitt/colors.jq";
      flake = false;
    };

    plib-jq = {
      url = "github:pschmitt/plib.jq";
      flake = false;
    };

    vi-motions = {
      url = "github:zsh-vi-more/vi-motions/c21a9e13be15166810e9487a015cd70c21229cf7";
      flake = false;
    };

    vi-quote = {
      url = "github:zsh-vi-more/vi-quote/13399086a4c31e8c0e09562ca0c4205ee4c055bd";
      flake = false;
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        flake-parts.follows = "flake-parts";
      };
    };

    nixos-config-private = {
      url = "github:pschmitt/nixos-config-private";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pre-commit-hooks.follows = "pre-commit-hooks";
      };
    };

    hypr-rdp = {
      url = "github:MuNeNiCK/hypr-rdp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprgrass = {
      url = "github:horriblename/hyprgrass";
      inputs.hyprland.follows = "hyprland";
    };
    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs = {
        hyprland.follows = "hyprland";
        nixpkgs.follows = "hyprland/nixpkgs";
      };
    };
    grim-hyprland = {
      url = "github:eriedaberrie/grim-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    jcalapi = {
      url = "github:pschmitt/jcalapi";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    jellysync = {
      url = "github:pschmitt/jellysync";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    lan-mouse = {
      url = "github:feschber/lan-mouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    luks-ssh-unlock = {
      url = "github:pschmitt/luks-ssh-unlock";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    rbw = {
      # main: its pinned browser packages are those of the last release.
      url = "github:pschmitt/rbw";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    tmux-slay = {
      url = "github:pschmitt/tmux-slay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    tmux-xpanes = {
      url = "github:greymd/tmux-xpanes";
      flake = false;
    };

    luks-mount = {
      url = "github:pschmitt/luks-mount.sh";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    lazyvim = {
      url = "github:pfassina/lazyvim-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    ldifj = {
      url = "github:pschmitt/ldifj";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-needsreboot = {
      # The bash version that actually works
      url = "git+https://codeberg.org/Mynacol/nixos-needsreboot.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # NOTE Caching is nice, maybe don't override nixpkgs here
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    printlabel = {
      url = "github:pschmitt/printlabel";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    # the myl family
    myl = {
      url = "github:pschmitt/myl";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    myl-discovery = {
      url = "github:pschmitt/myl-discovery";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    nbx = {
      url = "github:pschmitt/nbx";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    obs-cli = {
      url = "github:pschmitt/obs-cli";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    poor-tools = {
      url = "github:pschmitt/poor-tools";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        pre-commit-hooks.follows = "pre-commit-hooks";
      };
    };

    ruamel-fmt = {
      url = "github:pschmitt/ruamel-fmt";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    pschmitt-dev = {
      url = "github:pschmitt/pschmitt.dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sendmyl = {
      url = "github:pschmitt/sendmyl";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    shelly-ble-rpc = {
      url = "github:pschmitt/shelly-ble-rpc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    slack-react = {
      url = "github:pschmitt/slack-react";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    tdc = {
      url = "github:pschmitt/tdc";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    termux-tools = {
      url = "github:pschmitt/termux.sh";
      flake = false;
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    update-systemd-resolved = {
      url = "github:jonathanio/update-systemd-resolved";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };

    vodafone-station-cli = {
      url = "github:pschmitt/vodafone-station-cli";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    wezterm = {
      url = "git+https://github.com/wez/wezterm.git?dir=nix&submodules=1";
      # https://github.com/NixOS/nixpkgs/issues/348832
      # inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs =
    {
      nixpkgs,
      self,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-linux"
        "x86_64-linux"
      ];

      commonModules = [
        ./modules # custom modules
        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
        ./modules/syncthing/sops.nix
        inputs.nixos-config-private.nixosModules.default
      ];

      mkHost =
        hostname:
        {
          system,
          deviceType,
          homeManager ? false,
          hostModule ? ./hosts/${hostname},
          extraModules ? [ ],
        }:
        let
          isServer = deviceType == "server";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs outputs hostname;
            # Public modules the private flake input may import.
            publicModules = self.nixosModules;
          };
          modules =
            commonModules
            ++ extraModules
            ++ [
              hostModule
              {
                hardware.type = deviceType;
              }
            ]
            ++ nixpkgs.lib.optionals homeManager [
              ./home-manager
            ]
            ++ nixpkgs.lib.optionals isServer [
              inputs.srvos.nixosModules.mixins-terminfo
            ];
        };

      mkIso =
        modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs outputs;
          };
          modules = modules ++ [ { hardware.type = "installation-media"; } ];
        };
      minimalIsoModules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ./modules
      ];
      privateIsoFlakeModule = inputs.nixos-config-private.nixosModules.iso-private;
      privateIsoHostModule = ./hosts/iso-private;
      privateIsoModules =
        extraModules: [ privateIsoHostModule ] ++ extraModules ++ [ privateIsoFlakeModule ];
    in
    {
      lib.termux = {
        mkBundle =
          {
            modules ? [ ],
            extraSpecialArgs ? { },
          }:
          let
            system = "x86_64-linux";
            basePkgs = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
              };
            };
          in
          (import ./pkgs/termux/native { inherit basePkgs inputs; }).mkTermuxBundle {
            inherit modules extraSpecialArgs;
          };

        # Wrap a prepared Termux archive (built outside Nix, e.g. by
        # nixos-config-private's build-termux-bootstrap) as a reference-free
        # store path. Needs --impure since the archive lives outside the flake:
        #   nix build --impure --expr '(builtins.getFlake "path:/repo").lib.termux.mkCacheArchive {
        #     archive = /abs/termux-prefix.tar.gz; }'
        mkCacheArchive =
          {
            archive,
            archiveName ? baseNameOf (toString archive),
            system ? "x86_64-linux",
          }:
          nixpkgs.legacyPackages.${system}.callPackage ./pkgs/termux/cache-archive {
            archive = builtins.path {
              path = archive;
              name = "${archiveName}-source";
            };
            inherit archiveName;
          };

        mkPackageSet =
          { pkgs }:
          import ./pkgs/termux/native/package-set.nix {
            inherit inputs pkgs;
          };
      };

      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          customPackages = import ./pkgs { inherit pkgs inputs; };
          termuxNativePackages = nixpkgs.lib.optionalAttrs (system == "x86_64-linux") (
            let
              termuxNative = import ./pkgs/termux/native {
                basePkgs = pkgs;
                inherit inputs;
              };
              termuxHostBundles =
                nixpkgs.lib.mapAttrs
                  (
                    hostname: hostModule:
                    termuxNative.mkTermuxBundle {
                      modules = [ hostModule ];
                      extraSpecialArgs = { inherit hostname; };
                    }
                  )
                  {
                    mp4 = ./hosts/mp4;
                    p11 = ./hosts/p11;
                    zf10 = ./hosts/zf10;
                  };
              hostBundlePackages = nixpkgs.lib.mapAttrs' (
                hostname: bundle: nixpkgs.lib.nameValuePair "termux-native-${hostname}-bundle" bundle.bundle
              ) termuxHostBundles;
            in
            hostBundlePackages
          );
        in
        customPackages // termuxNativePackages
      );

      # below is to make "nix fmt" work
      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.nixfmt
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Every skill of this repo and the private one follows the Agent
          # Skills spec (frontmatter, name equals folder name) and passes
          # skills-lint (length, links, references, skill names). Both trees
          # are deployed side by side, so they are linted together. The CKS
          # skills only resolve names, and so do the upstream ones (the names
          # come from home-manager/devel/upstream-skills.nix).
          skills =
            let
              privateSkills = "${inputs.nixos-config-private}/hm/skills";
              upstreamSkills = import ./home-manager/devel/upstream-skills.nix {
                inherit (pkgs) fetchFromGitHub;
                inherit (self.packages.${system}) todoist-cli;
                inherit (inputs.llm-agents.packages.${system}) terminal-browser;
              };
              cksSkills = "${
                inputs.nixos-config-private.inputs.agent-skills.packages.${system}.default
              }/share/skills/cks-agent-skills";
              mergedSkills = pkgs.symlinkJoin {
                name = "resulting-skills-tree";
                paths = [
                  ./home-manager/devel/skills
                  privateSkills
                ];
              };
            in
            pkgs.runCommand "validate-skills"
              {
                nativeBuildInputs = [
                  self.packages.${system}.skills-ref
                  self.packages.${system}.skills-lint
                ];
              }
              ''
                for dir in ${mergedSkills}/*/; do
                  agentskills validate "$dir"
                done
                external=()
                for dir in ${nixpkgs.lib.concatMapStringsSep " " (path: "${path}/*/") upstreamSkills}; do
                  external+=(--external "$(basename "$dir")")
                done
                skills-lint \
                  --context ${cksSkills} \
                  "''${external[@]}" \
                  ${./home-manager/devel/skills} ${privateSkills}
                touch $out
              '';

          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              statix.enable = true;
              # Secret scanner (entropy + patterns, plus a repo-specific rule for
              # hardcoded shell credentials). Config + allowlist in .gitleaks.toml.
              gitleaks = {
                enable = true;
                name = "gitleaks";
                language = "system";
                pass_filenames = false;
                entry = "${pkgs.gitleaks}/bin/gitleaks git --staged --redact --no-banner --config .gitleaks.toml";
              };
            };
          };
        }
      );

      # Jobs for nixbot (self-hosted CI on rofl-10, see nixbot.toml): every
      # x86_64 host system and ISO image, supported custom packages and the
      # flake checks. Not in `checks` itself, which `nix flake check` builds
      # locally. Proprietary sources are seeded on rofl-10
      # (services/nix-proprietary-sources.nix).
      herculesCI =
        let
          inherit (nixpkgs) lib;
          # aarch64-linux builds natively on GitHub's arm runners
          # (.github/workflows/nix-build.yaml); the build nodes could only
          # emulate it.
          ciSystems = [ "x86_64-linux" ];
          # The packages output uses plain legacyPackages, where unfree
          # packages (or wrappers around one, like falcon-sensor-wiit)
          # refuse to evaluate; take those from an unfree-enabled set.
          # Decided from meta.available, which never forces a derivation
          # (forcing drvPath would run every package's IFD).
          unfreePackages =
            system:
            import ./pkgs {
              pkgs = import nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };
              inherit inputs;
            };
          unavailable =
            pkg:
            let
              result = builtins.tryEval (
                !(pkg.meta.available or true) || !(pkg.unwrapped.meta.available or true)
              );
            in
            result.success && result.value;
          ciPackages =
            system:
            let
              unfree = unfreePackages system;
            in
            lib.mapAttrs (
              name: pkg: if unavailable pkg then unfree.${name} or pkg else pkg
            ) self.packages.${system};
          buildable =
            system: name: pkg:
            let
              result = builtins.tryEval (
                lib.isDerivation pkg
                # Re-exported input; its own repository owns the CI build.
                && name != "browser-daemon"
                && (
                  if pkg ? passthru.ciBuildSystems then
                    lib.elem system pkg.passthru.ciBuildSystems
                  else
                    lib.meta.availableOn (lib.systems.elaborate system) pkg
                )
              );
            in
            # Keep packages whose check fails to evaluate: nixbot then
            # reports them as failed evaluations instead of silently
            # dropping them from the build.
            !result.success || result.value;
        in
        {
          inherit ciSystems;
          onPush.default.outputs = {
            hosts = lib.mapAttrs (_: host: host.config.system.build.toplevel) (
              lib.filterAttrs (
                _: host: lib.elem host.pkgs.stdenv.hostPlatform.system ciSystems
              ) self.nixosConfigurations
            );
            packages = lib.genAttrs ciSystems (system: lib.filterAttrs (buildable system) (ciPackages system));
            checks = lib.genAttrs ciSystems (system: self.checks.${system});
            images = lib.genAttrs [
              "iso"
              "iso-graphical"
              "iso-legacy"
              "iso-multios"
              "iso-private"
              "iso-private-legacy"
              "iso-private-multios"
            ] (host: self.nixosConfigurations.${host}.config.system.build.isoImage);
          };
          # nixbot.toml selects default.outputs as the build job set. Keep
          # effect derivations outside it; nixbot discovers all onPush effects.
          onPush.publish.outputs.effects = inputs.nixos-config-private.lib.ciEffects { flake = self; };
          onEvent = inputs.nixos-config-private.lib.ciEventEffects { };
        };

      # Devshell for bootstrapping
      # Accessible through 'nix develop' or 'nix-shell' (legacy)
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        in
        import ./shell.nix { inherit pkgs checks; }
      );

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # Build a Termux bundle with additional Home Manager modules and arguments.
      lib.mkTermuxBundle = import ./pkgs/termux/native/mkTermuxBundle.nix;

      # Public service modules, also handed to nixos-config-private as the
      # `publicModules` specialArg.
      nixosModules = {
        am-i-mullvad = ./profiles/features/network/snek/am-i-mullvad.nix;
        browser-daemon = ./modules/browser-daemon.nix;
        harmonia = ./services/harmonia.nix;
        http = ./services/http.nix;
        nfs-client = ./services/nfs/nfs-client.nix;
        sshfs = ./modules/sshfs.nix;
      };

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      homeModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations =
        (
          let
            hostConfigs = {
              # laptops
              ge2 = {
                system = "x86_64-linux";
                deviceType = "laptop";
                homeManager = true;
              };
              falcon-sensor-vm = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              gk4 = {
                system = "x86_64-linux";
                deviceType = "laptop";
                homeManager = true;
              };
              x13 = {
                system = "x86_64-linux";
                deviceType = "laptop";
                homeManager = true;
              };

              # servers
              lrz = {
                system = "x86_64-linux";
                deviceType = "server";
                homeManager = true;
              };
              fnuc = {
                system = "x86_64-linux";
                deviceType = "server";
                homeManager = true;
                hostModule = ./hosts/fnuc;
              };
              rofl-10 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-11 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-12 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-13 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-14 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-15 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              rofl-16 = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              oci-03 = {
                system = "aarch64-linux";
                deviceType = "server";
              };
              oci-01 = {
                system = "aarch64-linux";
                deviceType = "server";
              };
              test-delete-os = {
                system = "x86_64-linux";
                deviceType = "server";
              };
              test-delete-oci = {
                system = "aarch64-linux";
                deviceType = "server";
              };

              # Raspberry Pis
              pica4 = {
                system = "aarch64-linux";
                deviceType = "rpi";
                extraModules = [ "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" ];
              };
              # RPi Zero W — ARMv6 (BCM2835), camera + ustreamer only
              picaz = {
                system = "armv6l-linux";
                deviceType = "rpi";
                extraModules = [ "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi.nix" ];
              };
            };
          in
          nixpkgs.lib.mapAttrs mkHost hostConfigs
        )
        // {
          # installation media
          iso = mkIso (minimalIsoModules ++ [ ./hosts/iso ]);
          # MultiOS loopback boot needs the initrd to honor findiso=.
          iso-multios = mkIso (minimalIsoModules ++ [ ./hosts/iso ]);
          iso-graphical = mkIso [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares.nix"
            ./modules
            ./hosts/iso
          ];
          iso-private = mkIso (minimalIsoModules ++ privateIsoModules [ ]);
          iso-private-multios = mkIso (minimalIsoModules ++ privateIsoModules [ ]);
          iso-private-netboot = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs outputs;
            };
            modules = [
              "${nixpkgs}/nixos/modules/installer/netboot/netboot-minimal.nix"
              ./modules
              ./hosts/iso-private/networking.nix
              ./hosts/iso-private/packages.nix
              ./hosts/iso-private/quiet-boot.nix
              ./hosts/iso-private/ssh.nix
              privateIsoFlakeModule
              {
                hardware.type = "installation-media";
                system.stateVersion = "26.11";
              }
            ];
          };

          # legacy ISO images (no EFI, BIOS only!)
          iso-legacy = mkIso (
            minimalIsoModules
            ++ [
              ./hosts/iso
              ./workarounds/no-efi.nix
            ]
          );
          iso-private-legacy = mkIso (minimalIsoModules ++ privateIsoModules [ ./workarounds/no-efi.nix ]);
        };
    };

  nixConfig = {
    # fallback = true;
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
