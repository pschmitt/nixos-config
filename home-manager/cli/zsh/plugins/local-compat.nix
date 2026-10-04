{ lib, ... }:
{
  programs.zsh.initContent = lib.mkOrder 1370 ''
    # Unchanged local files still call these legacy names. They are adapters to
    # the Nix-managed loader; no Zinit state or manager is created in this shell.
    zinit::source-local-plugins() {
      zsh::source-local-plugins "$@"
    }

  '';
}
