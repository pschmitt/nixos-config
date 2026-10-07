# Commands the local plugins check for, from Nix instead of zinit's polaris
# bin. Termux imports the whole tools directory (./default.nix); jq.nix stays
# Termux-only here (zinit links ~/.config/jq/{colors,plib} on regular hosts)
# and the CLI profile installs tmux-xpanes itself.
{
  imports = [
    ./adb.nix
    ./bruvtab.nix
    ./fd.nix
    ./ketall.nix
    ./krew.nix
    ./kubectl-ksh.nix
    ./kubectl-socks5-proxy.nix
    ./kubectl-watch.nix
    ./luks-mount.nix
    ./nbx.nix
    ./netbird.nix
    ./tesmart.nix
    ./tmux-slay.nix
    ./yank.nix
  ];
}
