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

  # Local package integrations and temporary upstream fixes.
  modifications =
    final: prev:
    (import ./go-task.nix { inherit final prev; })
    // (import ./rbw.nix { inherit inputs final prev; })
    // (import ./wireguard-tools.nix { inherit final prev; })
    // (import ./pytr.nix { inherit prev; })
    // (import ./hotfixes/default.nix { inherit final prev; })
    // (import ./noctalia.nix { inherit inputs final prev; })
    // (import ./zsh-completions.nix { inherit inputs final prev; })
    // (import ./lan-mouse.nix { inherit inputs final; });

  # nixpkgs master, accessible through 'pkgs.master'
  master-packages = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      inherit (final.stdenv.hostPlatform) system;
      config = {
        allowUnfree = true;
        allowBroken = true;
      };
    };
  };

  flakes =
    final: _prev:
    let
      libMozilla = import (inputs.firefox-addons + "/../../lib/mozilla.nix") { inherit (final) lib; };
      buildMozillaXpiAddon = libMozilla.mkBuildMozillaXpiAddon { inherit (final) fetchurl stdenv; };
    in
    {
      firefox-addons = import inputs.firefox-addons {
        inherit buildMozillaXpiAddon;
        inherit (final) fetchurl lib stdenv;
      };
    };

  llm-agents = inputs.llm-agents.overlays.shared-nixpkgs;

  old-packages = final: _prev: {
    kubectl-123 = import inputs.nixpkgs-kubectl-123 { inherit (final.stdenv.hostPlatform) system; };
    terraform-157 = import inputs.nixpkgs-terraform-157 { inherit (final.stdenv.hostPlatform) system; };
  };
}
