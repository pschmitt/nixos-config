{ inputs, pkgs, ... }:
let
  httpasswdPkg = pkgs.writeShellScriptBin "htpasswd" ''
    exec ${pkgs.apacheHttpd}/bin/htpasswd "$@"
  '';
in
{

  imports = [
    ./ai.nix
    ./android.nix
    ./cloud.nix
    ./git.nix
    ./golang.nix
    ./jq.nix
    ./mani.nix
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

    inputs.ruamel-fmt.packages.${pkgs.stdenv.hostPlatform.system}.ruamel-fmt

    # task runners
    gnumake
    go-task
    just

    # encryption tools
    age
    sops
    ssh-to-age
  ];
}
