{ pkgs, ... }: {
  home.packages = [
    pkgs.aerc
    pkgs.gmailctl
    pkgs.neomutt
  ];

  home.file.".config/neomutt/nix" = {
    source = "${pkgs.neomutt}/share/neomutt";
  };

  # Create cache dir
  home.file.".cache/neomutt/bodies/.keep" = {
    source = builtins.toFile "keep" "";
  };
}
