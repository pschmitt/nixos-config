{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.programs.noctalia.settings.plugin_settings = {
    "pschmitt/battery-icon" = {
      battery_device = "BATT";
      charge_limit_as_full = true;
      full_at = 80;
      scale_percentage_to_charge_limit = false;
      show_fan_controls = false;
      show_tdp_controls = true;
    };

    "pschmitt/fan-control".thermal_zone = "thermal_zone1";
  };
}
