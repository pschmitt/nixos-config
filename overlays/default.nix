# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev:
    (import ./brotab.nix { inherit final prev; }) //
    (import ./hyprpicker.nix { inherit final prev; }) //
    (import ./openstack-cli.nix { inherit final prev; }) //
    (import ./libratbag.nix { inherit final prev; }) //
    (import ./piper.nix { inherit final prev; }) //
    # FIXME Remove this overlay once this is fixed in nixpkgs
    # The issue is that the source of amrnb ie.
    # http://www.penguin.cz/~utx/ftp/amr/amrnb-11.0.0.0.tar.bz2
    # is unreachable
    # (import ./amrnb.nix { inherit final prev; }) //
    # (import ./tmux.nix { inherit final prev; }) //
    { }; # Continue merging additional overlays as needed
  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };

    master = import inputs.nixpkgs-master {
      system = final.system;
      config.allowUnfree = true;
    };
  };

  old-packages = final: prev: {
    terraform-157 = import
      (builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/4ab8a3de296914f3b631121e9ce3884f1d34e1e5.tar.gz";
        sha256 = "sha256:095mc0mlag8m9n9zmln482a32nmbkr4aa319f2cswyfrln9j41cr";
      })
      {
        system = final.system;
      };
    kubectl-123 = import
      (builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/611bf8f183e6360c2a215fa70dfd659943a9857f.tar.gz";
        sha256 = "sha256:1rhrajxywl1kaa3pfpadkpzv963nq2p4a2y4vjzq0wkba21inr9k";
      })
      {
        system = final.system;
      };
  };
}
