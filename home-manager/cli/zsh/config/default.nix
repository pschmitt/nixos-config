# The Nix-managed Zsh config in ~/.config/zsh (ZDOTDIR): startup files,
# local plugins, functions and host/OS overlays.
{
  imports = [
    ./core.nix
    ./hashicorp-completions.nix
    ./portable.nix
    ./runtime.nix
    ./zhj.nix
    ../files
    ../plugins
    ../tools/cli.nix
  ];
}
