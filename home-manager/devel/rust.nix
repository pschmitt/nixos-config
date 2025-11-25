{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (fenix.complete.withComponents [
      "cargo"
      # "clippy"
      # "rust-src"
      "rustc"
      "rustfmt"
    ])
  ];
}
