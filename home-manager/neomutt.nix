{ pkgs, ... }: {
  home.packages = [ pkgs.neomutt ];

  home.file.".config/neomutt/nix" = {
    source = "${pkgs.neomutt}/share/neomutt";
  };
}
