{
  pkgss,
  inputs,
  pkgs,
  config,
  ...
}:
let
  container_image = "ghcr.io/pschmitt/jcalapi";
  container_tag = "latest";
  container_name = "jcalapi";
  config_file = "${config.custom.homeDirectory}/devel/private/calendar-events/jcalapi/.envrc-secrets";
in
{
  environment.systemPackages = with pkgs; [ deckmaster ];

  systemd.user.services.deckmaster = {
    enable = true;
    description = "An application to control your Elgato Stream Deck on Linux";
    documentation = [ "https://github.com/muesli/deckmaster" ];
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.deckmaster}/bin/deckmaster --verbose --deck %E/deckmaster/main.deck --brightness 33";
      Restart = "on-failure";
      RestartSec = "3";
    };
    wantedBy = [ "default.target" ];
  };
}
