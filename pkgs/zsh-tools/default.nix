{
  inputs,
  pkgs,
  ...
}:
{
  adb-sh = pkgs.callPackage ./adb-sh.nix { };
  adb-completions = pkgs.callPackage ./adb-completions.nix { };
  kubectl-ksh = pkgs.callPackage ./kubectl-ksh.nix { };
  kubectl-socks5-proxy = pkgs.callPackage ./kubectl-socks5-proxy.nix { };
  kubectl-watch = pkgs.callPackage ./kubectl-watch.nix { };
  netbird-cli = pkgs.callPackage ./netbird-cli.nix { };
  tesmart-cli = pkgs.callPackage ./tesmart-cli.nix { };
  zsh-diff-so-fancy = pkgs.callPackage ./zsh-diff-so-fancy.nix { inherit inputs; };
}
