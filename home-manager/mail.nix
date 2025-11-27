{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    inputs.myl.packages.${stdenv.hostPlatform.system}.myl
    inputs.myl-discovery.packages.${stdenv.hostPlatform.system}.myl-discovery
    inputs.sendmyl.packages.${stdenv.hostPlatform.system}.sendmyl

    aerc
    gmailctl
    gyb
    neomutt
  ];

  xdg = {
    configFile."neomutt/nix".source = "${pkgs.neomutt}/share/neomutt";
    # Create neomutt cache dir
    cacheFile."neomutt/bodies/.keep".text = "";
  };
}
