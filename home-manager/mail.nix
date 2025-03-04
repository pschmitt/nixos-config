{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    # mail
    inputs.myl.packages.${system}.myl
    inputs.myl-discovery.packages.${system}.myl-discovery
    inputs.sendmyl.packages.${system}.sendmyl

    # aerc
    (aerc.override { withNotmuch = false; })
    gmailctl
    neomutt
  ];

  home.file.".config/neomutt/nix" = {
    source = "${pkgs.neomutt}/share/neomutt";
  };

  # Create cache dir
  home.file.".cache/neomutt/bodies/.keep" = {
    source = builtins.toFile "keep" "";
  };
}
