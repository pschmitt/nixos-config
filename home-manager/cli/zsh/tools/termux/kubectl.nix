{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  kubectlCompletions = pkgs.runCommand "kubectl-zsh-completions" { } ''
    mkdir -p "$out"
    ${pkgs.buildPackages.kubectl}/bin/kubectl completion zsh > "$out/_kubectl"
  '';
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.kubectl ];
  termux.packages = lib.mkIf termuxMode [ "kubectl" ];
  xdg.configFile."zsh/completions/_kubectl".source = "${kubectlCompletions}/_kubectl";
}
