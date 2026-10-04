{ pkgs, ... }:
let
  kubectlCompletions = pkgs.runCommand "kubectl-zsh-completions" { } ''
    mkdir -p "$out"
    ${pkgs.buildPackages.kubectl}/bin/kubectl completion zsh > "$out/_kubectl"
  '';
in
{
  home.packages = [ pkgs.kubectl ];
  xdg.configFile."zsh/completions/_kubectl".source = "${kubectlCompletions}/_kubectl";
}
