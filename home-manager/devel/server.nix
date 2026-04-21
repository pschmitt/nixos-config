{
  inputs,
  pkgs,
  ...
}:
let
  httpasswdPkg = pkgs.writeShellScriptBin "htpasswd" ''
    exec ${pkgs.apacheHttpd}/bin/htpasswd "$@"
  '';
in
{
  imports = [
    ./git.nix
    ./jq.nix
    ./mani.nix
    ./nix.nix
    ./nodejs.nix
    ./python.nix
    ./sh.nix
  ];

  home.packages = with pkgs; [
    age
    envsubst
    flarectl
    gnumake
    go-task
    httpasswdPkg
    inotify-tools
    just
    sqlite
    sops
    ssh-to-age
    tmux-xpanes
    websocat
    inputs.ruamel-fmt.packages.${pkgs.stdenv.hostPlatform.system}.ruamel-fmt
  ];
}
