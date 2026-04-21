{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    (inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.complete.withComponents [
      "cargo"
      # "clippy"
      # "rust-src"
      "rustc"
      "rustfmt"
    ])
  ];
}
