# The Nix-managed shell uses an isolated dotDir and launcher; the regular
# yadm-owned Zsh startup files remain in place.
{
  imports = [
    ./core.nix
    ./hashicorp-completions.nix
    ./hm.nix
    ./portable.nix
    ./runtime.nix
    ./zhj.nix
    ../plugins
    ../tools/cli.nix
  ];
}
