{ pkgs, ... }:
{
  # Vimium C keeps its settings in storage.local, which home-manager can seed
  # (storage.js). The old Vimium only used storage.sync, hence vimium.nix.
  programs.firefox.profiles.default.extensions.settings.${pkgs.firefox-addons.vimium-c.addonId} = {
    force = true;
    settings = {
      # Vimium C matches plain URL prefixes (":" prefix optional) or regexes
      # (leading "^"), not Vimium's "*" globs.
      exclusionRules = [
        {
          passKeys = "";
          pattern = "^https?://mail\\.google\\.com/";
        }
        {
          passKeys = "";
          pattern = ":https://ha.brkn.lol";
        }
        {
          passKeys = "";
          pattern = ":http://10.5.1.10:8123";
        }
        {
          passKeys = "";
          pattern = "^https?://pikvm\\.";
        }
        {
          passKeys = "";
          pattern = "^https?://browser\\..*\\.brkn\\.lol";
        }
      ];

      # No unmaps: these keys are unbound in Vimium C (it errors on unmapping them).
      userDefinedCss = builtins.readFile ./vimium-c/theme.css;

      keyMappings = ''
        map <c-b> Vomnibar.activateTabs

        map <a-W> closeTabsOnRight

        map <c-6> visitPreviousTab

        map <c-h> Vomnibar.activateHistory
      '';
    };
  };
}
