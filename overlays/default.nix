{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions =
    final: _prev:
    let
      customPackages = import ../pkgs {
        pkgs = final;
        inherit inputs;
      };
    in
    customPackages
    // {
      # Include luks-ssh-unlock from the flake
      luks-ssh-unlock = inputs.luks-ssh-unlock.packages.${final.stdenv.hostPlatform.system}.default;
    };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications =
    final: prev:
    (import ./brotab.nix { inherit final prev; })
    // (import ./hass-cli.nix { inherit final prev; })
    // (import ./go-task.nix { inherit final prev; })
    # // (import ./netbird.nix { inherit final prev; })
    // (import ./paperless-ngx.nix { inherit final prev; })
    // (import ./rbw.nix { inherit final prev; })
    // (import ./wireguard-tools.nix { inherit final prev; })
    // (import ./hotfixes.nix { inherit inputs final prev; })
    // (import ./tmux.nix { inherit final prev; })
    // { }; # Continue merging additional overlays as needed
  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

    streamcontroller = import inputs.nixpkgs-streamcontroller {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  };

  flakes = final: prev: {
    firefox-addons = import inputs.firefox-addons {
      inherit (final) fetchurl;
      inherit (final) lib;
      inherit (final) stdenv;
    };
  };

  old-packages = final: prev: {
    # https://lazamar.co.uk/nix-versions/?channel=nixpkgs-unstable&package=kubectl
    kubectl-123 = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/611bf8f183e6360c2a215fa70dfd659943a9857f.tar.gz";
      sha256 = "sha256:1rhrajxywl1kaa3pfpadkpzv963nq2p4a2y4vjzq0wkba21inr9k";
    }) { inherit (final.stdenv.hostPlatform) system; };

    terraform-157 = import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/4ab8a3de296914f3b631121e9ce3884f1d34e1e5.tar.gz";
      sha256 = "sha256:095mc0mlag8m9n9zmln482a32nmbkr4aa319f2cswyfrln9j41cr";
    }) { inherit (final.stdenv.hostPlatform) system; };
  };
}
