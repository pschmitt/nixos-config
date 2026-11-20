# Commands the local plugins check for, from Nix instead of zinit's polaris
# bin.
{
  imports = [
    ./adb.nix
    ./bruvtab.nix
    ./fd.nix
    ./jq.nix
    ./ketall.nix
    ./ldif2json.nix
    ./krew.nix
    ./kubectl-ksh.nix
    ./kubectl-socks5-proxy.nix
    ./kubectl-watch.nix
    ./luks-mount.nix
    ./nbx.nix
    ./netbird.nix
    ./tables.nix
    ./teams-messages.nix
    ./tesmart.nix
    ./xcp.nix
    ./tmux-slay.nix
    ./yank.nix
  ];
}
