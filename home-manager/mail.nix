{ inputs, pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      inputs.myl.packages.${stdenv.hostPlatform.system}.myl
      inputs.myl-discovery.packages.${stdenv.hostPlatform.system}.myl-discovery
      inputs.sendmyl.packages.${stdenv.hostPlatform.system}.sendmyl

      aerc
      gmailctl
      neomutt
    ];

    file.".config/neomutt/nix".source = "${pkgs.neomutt}/share/neomutt";
  };

  # Create cache dir
  xdg.cacheFile."neomutt/bodies/.keep".text = "";
}
