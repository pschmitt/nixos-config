{ config, pkgs, ... }:
{
  # Access tokens for the user's own (unprivileged) nix commands.
  # The system-level GitHub token in profiles/global/nix/secrets.nix is
  # rendered root-only, so it only helps root/nix-daemon invocations (eg.
  # `sudo nixos-rebuild`), not plain `nix build`/`nix flake update` run as
  # this user — those hit GitHub's anonymous API rate limit instead.
  # git.wiit.one reuses the same PAT as glab (home-manager/work/glab.nix)
  # so private-repo flake inputs on that host resolve too.
  sops.secrets."nix/github_token" = {
    sopsFile = ../../secrets/shared.sops.yaml;
  };

  sops.templates."nix-access-tokens".content = ''
    access-tokens = github.com=${config.sops.placeholder."nix/github_token"} git.wiit.one=${
      config.sops.placeholder."glab/git.wiit.one/token"
    }
  '';

  nix.extraOptions = ''
    !include ${config.sops.templates."nix-access-tokens".path}
  '';

  home.packages = with pkgs; [
    alejandra
    cachix
    niv
    nix-init
    nixfmt
    nixos-anywhere
    nixos-generators
    nixpkgs-fmt
    nvd
    statix
  ];
}
