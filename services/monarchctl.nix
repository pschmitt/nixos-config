# monarchctl: CLI + TUI for the Monarch server (services/monarch.nix)
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.monarch.nixosModules.monarchctl ];

  # shared: also provisioned on the server as the admin's managed API token
  sops.secrets."monarch/cli/token" = {
    owner = config.mainUser.username;
  };

  programs.monarchctl = {
    enable = true;
    package = inputs.monarch.packages.${pkgs.stdenv.hostPlatform.system}.monarchctl;
    settings.url = "https://monarch.${config.domains.main}";
    tokenFile = config.sops.secrets."monarch/cli/token".path;
  };
}
