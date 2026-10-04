{
  lib,
  pkgs,
  ...
}:
let
  argocdCompletions = pkgs.runCommand "argocd-zsh-completions" { } ''
    mkdir -p "$out"
    ${pkgs.buildPackages.argocd}/bin/argocd completion zsh > "$out/_argocd"
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  home.packages = [ pkgs.argocd ];
  xdg.configFile."zsh/completions/_argocd".source = "${argocdCompletions}/_argocd";
}
