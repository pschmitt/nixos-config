{ inputs, ... }:
{
  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry = {
      nixos-config.flake = inputs.self;
      nixpkgs.flake = inputs.nixpkgs;
    };
  };
}
