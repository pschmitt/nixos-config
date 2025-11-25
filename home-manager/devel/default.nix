{ pkgs, ... }:
let
  httpasswdPkg = pkgs.writeShellScriptBin "htpasswd" ''
    exec ${pkgs.apacheHttpd}/bin/htpasswd "$@"
  '';
in
{

  imports = [
    ./ai.nix
    ./android.nix
    ./git.nix
    ./nix.nix
    ./python.nix
    ./rust.nix
    ./sh.nix
    ./zsh.nix
  ];

  home.packages = with pkgs; [
    envsubst
    flarectl
    httpasswdPkg
    inotify-tools
    sqlite
    tmux-xpanes
    websocat

    # task runners
    gnumake
    go-task
    just
  ];
}
