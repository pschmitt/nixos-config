# The Nix-managed Zsh startup files in ~/.config/zsh (ZDOTDIR). yadm only
# provides the local plugins, functions and host/OS overlays beside them.
{
  imports = [
    ./core.nix
    ./hashicorp-completions.nix
    ./hm.nix
    ./portable.nix
    ./runtime.nix
    ./zhj.nix
    ../files
    ../plugins
    ../tools/cli.nix
  ];
}
