{ inputs, ... }:
{
  # Module import only: `programs.noctalia.enable` is opt-in per host (see
  # profiles/laptop/noctalia.nix), same as dank.nix.
  imports = [
    inputs.noctalia.homeModules.default
  ];
}
