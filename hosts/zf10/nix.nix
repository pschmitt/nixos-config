{ inputs, ... }:
{
  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry = {
      # Resolve the repository when used, without embedding this checkout in
      # every Android activation package.
      nixos-config.to = {
        type = "github";
        owner = "pschmitt";
        repo = "nixos-config";
      };
      nixpkgs.flake = inputs.nixpkgs;
    };
  };
}
