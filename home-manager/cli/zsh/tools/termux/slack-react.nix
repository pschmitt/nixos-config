{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux-native/package-set.nix {
    inherit inputs pkgs;
  };
  slackReact =
    if termuxMode then
      termuxPackageSet.termuxPackages.slack-react
    else
      inputs.slack-react.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = [ slackReact ];
}
