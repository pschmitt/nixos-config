{ config, lib, ... }:
{
  # Only one PolicyKit agent can register per session, so this is mkDefault:
  # a desktop that brings its own agent (noctalia's built-in one, see
  # profiles/laptop/noctalia.nix) turns it off rather than racing it.
  services.hyprpolkitagent.enable = lib.mkDefault true;

  systemd.user.services.hyprpolkitagent.Service = lib.mkIf config.services.hyprpolkitagent.enable {
    Restart = "on-failure";
    RestartSec = 5;
  };
}
