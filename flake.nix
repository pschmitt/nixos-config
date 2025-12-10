{
  description = "pschmitt's nix collection";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; # unstable by default
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    # prs
    nixpkgs-streamcontroller.url = "github:NixOS/nixpkgs/pull/416567/head";

    # attic = {
    #   url = "github:zhaofengli/attic";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    anika-blue = {
      url = "github:pschmitt/anika-blue";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stricknani = {
      url = "github:pschmitt/stricknani";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    docker-compose-bulk = {
      url = "github:pschmitt/docker-compose-bulk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix/monthly";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    falcon-sensor = {
      url = "github:benley/falcon-sensor-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # flake-registry = {
    #   url = "github:NixOS/flake-registry";
    #   flake = false;
    # };

    # flake-utils = {
    #   url = "github:numtide/flake-utils";
    # };

    flatpaks = {
      # https://github.com/GermanBread/declarative-flatpak/blob/dev/docs/branches.md
      url = "github:in-a-dil-emma/declarative-flatpak/v3.1.0";
      # NOTE Do *not* override nixpkgs, it is not supported
    };

    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
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

    hacompanion = {
      url = "github:tobias-kuendig/hacompanion";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland and cie {{{
    hyprland = {
      url = "github:hyprwm/Hyprland/v0.52.2";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprdynamicmonitors = {
      url = "github:fiffeek/hyprdynamicmonitors";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "hyprland";
    };

    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "hyprland";
    };

    # hyprland plugins
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/v0.52.0";
      inputs.hyprland.follows = "hyprland";
    };

    hyprshell = {
      url = "github:H3rmt/hyprshell?ref=hyprshell-release";
      inputs = {
        home-manager.follows = "home-manager";
        hyprland.follows = "hyprland";
        nixpkgs.follows = "nixpkgs";
      };
    };

    hyprtasking = {
      # upstream url
      # url = "github:raybbian/hyprtasking";

      # https://github.com/raybbian/hyprtasking/pull/82
      url = "github:Megakuul/hyprtasking";
      inputs.hyprland.follows = "hyprland";
    };

    hyprgrass = {
      # NOTE commit bcbe929cca73f273f3a5927298851662c31ef27c introduces
      # compilation issues with hyprland 0.52.x
      # https://github.com/horriblename/hyprgrass/commits/main/
      url = "github:horriblename/hyprgrass/8c57cc1cb13361774ddde67bfc75ab04e9b13f28";
      inputs.hyprland.follows = "hyprland"; # IMPORTANT
    };

    grim-hyprland = {
      url = "github:eriedaberrie/grim-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs.hyprland.follows = "hyprland";
    };

    # end of plugins

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    xdph = {
      # url = "github:hyprwm/xdg-desktop-portal-hyprland";
      url = "github:SamSaffron/xdg-desktop-portal-hyprland/better-picker";
      inputs.nixpkgs.follows = "hyprland";
    };

    # hyprland end }}}

    jcalapi = {
      url = "github:pschmitt/jcalapi";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jellysync = {
      url = "github:pschmitt/jellysync";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lan-mouse = {
      url = "github:feschber/lan-mouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    luks-ssh-unlock = {
      url = "github:pschmitt/luks-ssh-unlock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tmux-slay = {
      url = "github:pschmitt/tmux-slay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    luks-mount = {
      url = "github:pschmitt/luks-mount.sh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ldifj = {
      url = "github:pschmitt/ldifj";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-needsreboot = {
      # url = "https://codeberg.org/Mynacol/nixos-needsreboot/archive/main.tar.gz";
      # same, but with a different output
      # url = "https://flakehub.com/f/wimpysworld/nixos-needsreboot/*.tar.gz";
      # The bash version that actually works
      url = "https://codeberg.org/Mynacol/nixos-needsreboot/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # NOTE Caching is nice, maybe don't override nixpkgs here
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wayland = {
      url = "github:nix-community/nixpkgs-wayland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # the myl family
    myl = {
      url = "github:pschmitt/myl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    myl-discovery = {
      url = "github:pschmitt/myl-discovery";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    obs-cli = {
      url = "github:pschmitt/obs-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    poor-tools = {
      url = "github:pschmitt/poor-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ruamel-fmt = {
      url = "github:pschmitt/ruamel-fmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pschmitt-dev = {
      url = "github:pschmitt/pschmitt.dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sendmyl = {
      url = "github:pschmitt/sendmyl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    slack-react = {
      url = "github:pschmitt/slack-react";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tdc = {
      url = "github:pschmitt/tdc";
      inputs.nixpkgs.follows = "nixpkgs";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # FIXME it does not build currently! (2025-11-01)
    # vicinae = {
    #   url = "github:vicinaehq/vicinae";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    vodafone-station-cli = {
      url = "github:pschmitt/vodafone-station-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      # https://github.com/NixOS/nixpkgs/issues/348832
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zjstatus = {
    #   url = "github:dj95/zjstatus";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # HOTFIXES: Overrides, pending PRs, etc
    # droidcam-obs.url = "github:NixOS/nixpkgs?ref=refs/pull/382559/head";
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
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      commonModules = [
        ./modules/custom.nix
        ./modules/main-user.nix
        ./modules/domains.nix
        ./modules/hardware.nix

        inputs.disko.nixosModules.disko
        inputs.sops-nix.nixosModules.sops
      ];

      mkHost =
        hostname:
        {
          system,
          deviceType,
          homeManager ? false,
        }:
        let
          isServer = deviceType == "server";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs outputs;
          };
          modules =
            commonModules
            ++ [
              ./hosts/${hostname}
              {
                hardware.type = deviceType;
                home-manager.enabled = homeManager;
              }
            ]
            ++ nixpkgs.lib.optionals homeManager [
              ./home-manager
            ]
            ++ nixpkgs.lib.optionals isServer [
              inputs.srvos.nixosModules.mixins-terminfo
            ];
        };
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          customPackages = import ./pkgs { inherit pkgs inputs; };
        in
        customPackages
      );

      # below is to make "nix fmt" work
      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.nixfmt-rfc-style
      );

      checks = forAllSystems (system: {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style.enable = true;
            statix.enable = false;
            pre-commit-hook-ensure-sops = {
              enable = true;
              files = ".+.sops.yaml$";
            };
          };
        };
      });

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

      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      # nixosModules = import ./modules/nixos;

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # homeManagerModules = import ./modules/home-manager;

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
              oci-03 = {
                system = "aarch64-linux";
                deviceType = "server";
              };
            };
          in
          nixpkgs.lib.mapAttrs mkHost hostConfigs
        )
        // {
          pica4 = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = {
              inherit inputs outputs;
            };
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
              inputs.sops-nix.nixosModules.sops
              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/pica4
              { hardware.type = "rpi"; }
            ];
          };

          # installation media
          iso = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/iso
              { hardware.type = "installation-media"; }
            ];
          };
          iso-graphical = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares.nix"

              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/iso
              { hardware.type = "installation-media"; }
            ];
          };
          iso-xmr = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/iso-xmr
              { hardware.type = "installation-media"; }
            ];
          };

          # legacy ISO images (no EFI, BIOS only!)
          iso-legacy = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/iso
              ./workarounds/no-efi.nix
              { hardware.type = "installation-media"; }
            ];
          };
          iso-xmr-legacy = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/channel.nix"
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./modules/custom.nix
              ./modules/main-user.nix
              ./modules/domains.nix
              ./modules/hardware.nix
              ./hosts/iso-xmr
              ./workarounds/no-efi.nix
              { hardware.type = "installation-media"; }
            ];
          };
        };
    };

  nixConfig = {
    # fallback = true;
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };
}
