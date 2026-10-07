# Commands the local plugins check for, from Nix instead of zinit's polaris
# bin. Termux imports the whole tools directory (./default.nix); the CLI
# profile installs tmux-xpanes itself.
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
    ./tesmart.nix
    ./xcp.nix
    ./tmux-slay.nix
    ./yank.nix
  ];
}
