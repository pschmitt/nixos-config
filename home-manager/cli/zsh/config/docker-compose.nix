{ lib, ... }:
{
  # Shared with the servers' NixOS-level shell config (../shared)
  programs.zsh.initContent = lib.mkOrder 1200 (builtins.readFile ../shared/docker-compose.sh);
}
