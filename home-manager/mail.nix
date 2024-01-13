{ pkgs, ... }: {
  home.packages = [
    pkgs.aerc
    pkgs.neomutt
  ];

  home.file.".config/neomutt/nix" = {
    source = "${pkgs.neomutt}/share/neomutt";
  };
}
